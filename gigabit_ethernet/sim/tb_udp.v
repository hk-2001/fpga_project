`timescale 1ns / 1ps
//============================================================================
// tb_udp : UDP 接收(伪首部校验 + 端口过滤) + 回显发送 整链仿真
//
// 被测链路 : mac_rx -> ip_rx -> udp_rx -> udp_tx(grant=1) -> 抓取发送字节
// 被测模块 : mac_rx, ip_rx, udp_rx, udp_tx, crc32_d8, xpm_fifo_sync(仿真模型)
//
// 激励帧   : 源端口 12345 -> 目的端口 5000, 数据 "PING"(4字节)
//            IP 总长度 = 0x20 = 32 -> UDP 长度 12 -> 帧长 50 字节
//
// 测试点:
//   1) 回显帧长度 = 50 字节
//   2) 回显源端口   = 5000   (本板端口)
//   3) 回显目的端口 = 12345  (= 发送方的源端口)
//   4) UDP 长度     = 12
//   5) 数据区 "PING" 原样回显(含最后1字节 'G', 用于验证数据区边界)
//   6) 回显帧自身 FCS 校验通过
//
// 【重点】第5项检查偏移 45(最后一个数据字节)。此前 udp_tx 存在差一错误
//        (bcnt < data_last), 会把最后1字节发成 0x00, 现已修复为 <= 。
//============================================================================
module tb_udp;

    reg         clk = 0, rst = 1;
    reg  [7:0]  d = 0;
    reg         dv = 0;
    integer     errors = 0;
    integer     k;

    always #4 clk = ~clk;                 // 125MHz 时钟(必须有)

    // ---- mac_rx ----
    wire        sof, en, eof, crc_ok;
    wire [7:0]  data;
    wire [47:0] dmac, smac;
    wire [15:0] etype;
    mac_rx u_mac (.clk(clk), .rst(rst), .gmii_d(d), .gmii_dv(dv), .gmii_rx_er(1'b0),
        .sof(sof), .data(data), .en(en), .eof(eof),
        .dst_mac(dmac), .src_mac(smac), .eth_type(etype), .crc_ok(crc_ok));

    // ---- ip_rx ----
    wire        p_sof, p_en, p_eof, ip_ok;
    wire [7:0]  p_data;
    wire [15:0] payload_len;
    wire [7:0]  protocol;
    wire [31:0] src_ip;
    ip_rx #(.BOARD_IP(32'hC0A8_017B)) u_ip (
        .clk(clk), .rst(rst), .sof(sof), .en(en), .data(data),
        .eth_type(etype), .crc_ok(crc_ok),
        .p_sof(p_sof), .p_data(p_data), .p_en(p_en), .p_eof(p_eof),
        .payload_len(payload_len), .protocol(protocol),
        .src_ip(src_ip), .ip_ok(ip_ok));

    // ---- udp_rx ----
    wire        pkt_en;
    wire [15:0] sport, ulen;
    wire [31:0] rip;
    wire [47:0] rmac;
    wire [7:0]  fifo_dout;
    wire        fifo_empty, fifo_rd;
    udp_rx #(.BOARD_IP(32'hC0A8_017B), .LOCAL_UDP_PORT(16'h1388)) u_udp_rx (
        .clk(clk), .rst(rst),
        .p_sof(p_sof), .p_en(p_en), .p_eof(p_eof), .p_data(p_data),
        .payload_len(payload_len),
        .src_ip(src_ip), .src_mac(smac), .ip_ok(ip_ok),
        .pkt_en(pkt_en), .sport(sport), .udp_len(ulen),
        .rip(rip), .rmac(rmac),
        .fifo_rd(fifo_rd), .fifo_dout(fifo_dout), .fifo_empty(fifo_empty));

    // ---- udp_tx ----
    wire        tx_req, tx_done, tx_en;
    wire [7:0]  tx_data;
    udp_tx #(.BOARD_MAC(48'h00_11_22_33_44_55), .BOARD_IP(32'hC0A8_017B),
             .LOCAL_UDP_PORT(16'h1388)) u_udp_tx (
        .clk(clk), .rst(rst),
        .send_en(pkt_en), .sport(sport), .udp_len(ulen),
        .dst_ip(rip), .dst_mac(rmac),
        .req(tx_req), .grant(1'b1), .done(tx_done),
        .tx_en(tx_en), .tx_data(tx_data),
        .fifo_rd(fifo_rd), .fifo_dout(fifo_dout), .fifo_empty(fifo_empty));

    // ---- 发送字节抓取 + CRC 回灌自检 ----
    reg [7:0] txbuf [0:79];
    integer   txcnt;
    reg       chk_en = 0;
    reg [7:0] chk_d;
    wire [31:0] chk_crc;
    wire        chk_ok;
    // crc_ok 是单拍脉冲, 用锁存器记录以免错过
    reg         chk_ok_seen = 1'b0;
    always @(posedge clk) if (chk_ok) chk_ok_seen <= 1'b1;
    crc32_d8 u_chk (.clk(clk), .rst(rst), .data(chk_d),
                    .data_en(chk_en), .crc_out(chk_crc), .crc_ok(chk_ok));

    always @(posedge clk) begin
        chk_en <= tx_en;
        chk_d  <= tx_data;
        if (tx_en) begin
            txbuf[txcnt] = tx_data;
            txcnt = txcnt + 1;
        end
    end

    // UDP 帧(50字节, 含正确FCS): 12345 -> 5000, 数据 "PING"
    reg [7:0] frame [0:49];
    initial begin
        frame[0]=8'h00; frame[1]=8'h11; frame[2]=8'h22; frame[3]=8'h33;
        frame[4]=8'h44; frame[5]=8'h55; frame[6]=8'h00; frame[7]=8'h11;
        frame[8]=8'h22; frame[9]=8'h33; frame[10]=8'h44; frame[11]=8'h66;
        frame[12]=8'h08; frame[13]=8'h00; frame[14]=8'h45; frame[15]=8'h00;
        frame[16]=8'h00; frame[17]=8'h20; frame[18]=8'h00; frame[19]=8'h00;
        frame[20]=8'h40; frame[21]=8'h00; frame[22]=8'h40; frame[23]=8'h11;
        frame[24]=8'hB6; frame[25]=8'h9D; frame[26]=8'hC0; frame[27]=8'hA8;
        frame[28]=8'h01; frame[29]=8'h64; frame[30]=8'hC0; frame[31]=8'hA8;
        frame[32]=8'h01; frame[33]=8'h7B; frame[34]=8'h30; frame[35]=8'h39;
        frame[36]=8'h13; frame[37]=8'h88; frame[38]=8'h00; frame[39]=8'h0C;
        frame[40]=8'h99; frame[41]=8'h54; frame[42]=8'h50; frame[43]=8'h49;
        frame[44]=8'h4E; frame[45]=8'h47; frame[46]=8'hED; frame[47]=8'hA2;
        frame[48]=8'h95; frame[49]=8'h1A;
    end

    initial begin
        rst = 1; txcnt = 0; #20; rst = 0; #10;

        // 发送: 前导码 + SFD + 帧体
        // 在下降沿驱动, 避免与 DUT 上升沿采样竞争
        for (k = 0; k < 7; k = k + 1) begin @(negedge clk); d = 8'h55; dv = 1; end
        @(negedge clk); d = 8'hD5;
        for (k = 0; k < 50; k = k + 1) begin @(negedge clk); d = frame[k]; end
        @(negedge clk); dv = 0; d = 0;

        wait (tx_done == 1'b1);
        // chk 路径比 tx_en 晚 2 拍, 且 crc_ok 是单拍脉冲, 需留足时间
        #100;

        // ---- 检查项(不满足则 errors+1, 说明见注释) ----
        if (txcnt !== 50)                    errors = errors + 1;  // 回显帧应为 50 字节
        if ({txbuf[34],txbuf[35]} !== 16'h1388) errors = errors + 1;  // 源端口应为 5000
        if ({txbuf[36],txbuf[37]} !== 16'h3039) errors = errors + 1;  // 目的端口应为 12345
        if ({txbuf[38],txbuf[39]} !== 16'h000C) errors = errors + 1;  // UDP长度应为 12
        if (txbuf[42] !== 8'h50)             errors = errors + 1;  // 数据首字节应为 'P'
        if (txbuf[45] !== 8'h47)             errors = errors + 1;  // 数据末字节应为 'G'(验证边界修复)
        if (!chk_ok_seen)                    errors = errors + 1;  // 回显帧 FCS 应校验通过

        #30;
        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_udp: PASS ====");
        else             $display("==== tb_udp: %0d 个错误 FAIL ====", errors);
        $finish;
    end

    // 看门狗: 防止始终等不到回显时仿真无限运行
    initial begin
        #100000;
        $display("==== tb_udp: 超时(未收到回显) FAIL ====");
        $finish;
    end

endmodule
