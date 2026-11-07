`timescale 1ns / 1ps
//============================================================================
// tb_arp_rx : ARP 接收 + 缓存学习 + ARP 应答发送 整链仿真
//
// 被测模块 : mac_rx, arp_rx, arp_cache, arp_tx, crc32_d8
//
// 测试点:
//   1) 解析     : 询问本板IP的 ARP 请求 -> 正确提取请求者 IP/MAC
//   2) 缓存学习 : arp_cache 能学到 192.168.1.100 -> 00:11:22:33:44:66
//   3) 应答帧长 : 必须为 64 字节(以太网最小帧长, ARP载荷28需填充18字节)
//   4) 应答内容 : EtherType=0x0806, 操作码=2, SPA=本板IP, TPA=请求者IP
//   5) 填充区   : 偏移 42~59 必须为 0x00
//   6) FCS      : 应答帧自身 CRC 校验通过
//
// arp_tx 发送 64 字节(原先只有 46 字节, 属超短帧会被网卡丢弃)
//============================================================================
module tb_arp_rx;

    reg         clk = 0, rst = 1;
    reg  [7:0]  d = 0;
    reg         dv = 0;
    integer     errors = 0;
    integer     k;

    always #4 clk = ~clk;                 // 125MHz 时钟(必须有, 否则仿真空跑)

    // ---- mac_rx ----
    wire        sof, en, eof, crc_ok;
    wire [7:0]  data;
    wire [47:0] dmac, smac;
    wire [15:0] etype;
    mac_rx u_mac (.clk(clk), .rst(rst), .gmii_d(d), .gmii_dv(dv), .gmii_rx_er(1'b0),
        .sof(sof), .data(data), .en(en), .eof(eof),
        .dst_mac(dmac), .src_mac(smac), .eth_type(etype), .crc_ok(crc_ok));

    // ---- arp_rx ----
    wire        update_en, reply_en;
    wire [31:0] update_ip, req_ip;
    wire [47:0] update_mac, req_mac;
    arp_rx #(.BOARD_IP(32'hC0A8_017B)) u_arp_rx (
        .clk(clk), .rst(rst), .sof(sof), .en(en), .data(data),
        .eth_type(etype), .crc_ok(crc_ok),
        .update_en(update_en), .update_ip(update_ip), .update_mac(update_mac),
        .reply_en(reply_en), .req_ip(req_ip), .req_mac(req_mac));

    // ---- arp_cache ----
    // 用 reg 驱动查询口(不能用层次化引用给 input 端口赋值)
    reg         query_en_r = 1'b0;
    reg  [31:0] query_ip_r = 32'd0;
    wire        cache_hit;
    wire [47:0] cache_mac;
    arp_cache u_cache (
        .clk(clk), .rst(rst),
        .wr_en(update_en), .wr_ip(update_ip), .wr_mac(update_mac),
        .query_en(query_en_r), .query_ip(query_ip_r),
        .hit(cache_hit), .mac_out(cache_mac));

    // ---- arp_tx (grant 恒为 1, 直接发送) ----
    wire        tx_req, tx_done, tx_en;
    wire [7:0]  tx_data;
    arp_tx #(.BOARD_MAC(48'h00_11_22_33_44_55), .BOARD_IP(32'hC0A8_017B)) u_arp_tx (
        .clk(clk), .rst(rst),
        .reply_en(reply_en), .req_ip(req_ip), .req_mac(req_mac),
        .req(tx_req), .grant(1'b1), .done(tx_done),
        .tx_en(tx_en), .tx_data(tx_data));

    // ---- 应答帧 FCS 自检: 把发出的字节回灌进 CRC 校验器 ----
    reg        chk_en;
    reg  [7:0] chk_d;
    wire [31:0] chk_crc;
    wire        chk_ok;
    // crc_ok 现在是"单拍脉冲", 用锁存器把它记录下来, 避免采样时机错过
    reg         chk_ok_seen = 1'b0;
    always @(posedge clk) if (chk_ok) chk_ok_seen <= 1'b1;
    crc32_d8 u_chk (.clk(clk), .rst(rst), .data(chk_d),
                    .data_en(chk_en), .crc_out(chk_crc), .crc_ok(chk_ok));

    // 抓取发出的应答帧
    reg [7:0] rxbuf [0:63];
    integer   rxcnt;

    // ---- ARP 请求帧(广播, 46字节含FCS) ----
    reg [7:0] frame [0:45];
    initial begin
        frame[0]=8'hFF; frame[1]=8'hFF; frame[2]=8'hFF; frame[3]=8'hFF;
        frame[4]=8'hFF; frame[5]=8'hFF; frame[6]=8'h00; frame[7]=8'h11;
        frame[8]=8'h22; frame[9]=8'h33; frame[10]=8'h44; frame[11]=8'h66;
        frame[12]=8'h08; frame[13]=8'h06; frame[14]=8'h00; frame[15]=8'h01;
        frame[16]=8'h08; frame[17]=8'h00; frame[18]=8'h06; frame[19]=8'h04;
        frame[20]=8'h00; frame[21]=8'h01; frame[22]=8'h00; frame[23]=8'h11;
        frame[24]=8'h22; frame[25]=8'h33; frame[26]=8'h44; frame[27]=8'h66;
        frame[28]=8'hC0; frame[29]=8'hA8; frame[30]=8'h01; frame[31]=8'h64;
        frame[32]=8'h00; frame[33]=8'h00; frame[34]=8'h00; frame[35]=8'h00;
        frame[36]=8'h00; frame[37]=8'h00; frame[38]=8'hC0; frame[39]=8'hA8;
        frame[40]=8'h01; frame[41]=8'h7B; frame[42]=8'hE6; frame[43]=8'hD2;
        frame[44]=8'hF3; frame[45]=8'hEB;
    end

    // 抓取发送字节并回灌 CRC
    always @(posedge clk) begin
        chk_en <= tx_en;
        chk_d  <= tx_data;
        if (tx_en) begin
            rxbuf[rxcnt] = tx_data;
            rxcnt = rxcnt + 1;
        end
    end

    initial begin
        rst = 1; rxcnt = 0; chk_en = 0; #20; rst = 0; #10;

        // 发送 ARP 请求帧
        // 在下降沿驱动, 避免与 DUT 上升沿采样竞争
        for (k = 0; k < 7; k = k + 1) begin @(negedge clk); d = 8'h55; dv = 1; end
        @(negedge clk); d = 8'hD5;
        for (k = 0; k < 46; k = k + 1) begin @(negedge clk); d = frame[k]; end
        @(negedge clk); dv = 0; d = 0;

        // 等待 arp_tx 发完
        wait (tx_done == 1'b1);
        @(posedge clk);

        // ---- 1) 解析结果 ----
        if (req_ip  !== 32'hC0A8_0164)       errors = errors + 1;  // 请求者IP应为 192.168.1.100
        if (req_mac !== 48'h00_11_22_33_44_66) errors = errors + 1;  // 请求者MAC应为 00:11:22:33:44:66

        // ---- 2) 缓存学习(查询一次) ----
        // 查询后 hit 是寄存器的(下一拍有效), 必须在撤掉 query_en 之前读
        query_en_r = 1'b1; query_ip_r = 32'hC0A8_0164;
        @(posedge clk); #1;
        if (!cache_hit)                       errors = errors + 1;  // ARP缓存应命中
        if (cache_mac !== 48'h00_11_22_33_44_66) errors = errors + 1;  // 缓存MAC应正确
        query_en_r = 1'b0;
        @(posedge clk);

        // ---- 3) 应答帧长度必须为 64(最小帧长) ----
        if (rxcnt !== 64)                     errors = errors + 1;  // 应答帧应为64字节

        // ---- 4) 应答帧内容 ----
        if ({rxbuf[12],rxbuf[13]} !== 16'h0806) errors = errors + 1;  // EtherType应为 0x0806(ARP)
        if ({rxbuf[20],rxbuf[21]} !== 16'h0002) errors = errors + 1;  // 操作码应为 2(应答)
        if ({rxbuf[28],rxbuf[29],rxbuf[30],rxbuf[31]} !== 32'hC0A8_017B)
                                               errors = errors + 1;  // 发送方IP应为本板 192.168.1.123
        if ({rxbuf[38],rxbuf[39],rxbuf[40],rxbuf[41]} !== 32'hC0A8_0164)
                                               errors = errors + 1;  // 目标IP应为请求者 192.168.1.100

        // ---- 5) 填充区 42~59 必须为 0 ----
        for (k = 42; k < 60; k = k + 1)
            if (rxbuf[k] !== 8'h00)           errors = errors + 1;  // 偏移42~59应为填充0x00

        // ---- 6) 应答帧 FCS ----
        // crc_ok 是单拍脉冲, 且 chk 路径比 tx_en 晚 2 拍, 需留足时间
        #100;
        if (!chk_ok_seen)                      errors = errors + 1;  // 应答帧FCS应校验通过

        #30;
        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_arp_rx: PASS ====");
        else             $display("==== tb_arp_rx: %0d 个错误 FAIL ====", errors);
        $finish;
    end

endmodule
