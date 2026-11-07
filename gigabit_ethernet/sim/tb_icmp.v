`timescale 1ns / 1ps
//============================================================================
// tb_icmp : ICMP 接收解析 + Echo 应答发送 整链仿真
//
// 被测链路 : mac_rx -> ip_rx -> icmp_rx -> icmp_tx(grant=1) -> 抓取发送字节
// 被测模块 : mac_rx, ip_rx, icmp_rx, icmp_tx, crc32_d8, xpm_fifo_sync(仿真模型)
//
// 测试点:
//   1) 应答帧长度 = 54 字节 (14 MAC头 + 20 IP头 + 8 ICMP头 + 8数据 + 4 FCS)
//   2) ICMP 类型 = 0 (Echo 应答,  请求帧里是 8)
//   3) ID / SEQ 原样返回
//   4) ICMP 校验和 = 请求0x6668 + 0x0800 = 0x6E68 (Type 8->0 的反码修正)
//   5) 数据区 "abcdefgh" 原样回显(含最后1字节, 用于验证数据区边界)
//   6) 应答帧源 IP = 本板 IP
//   7) 应答帧自身 FCS 校验通过
//
// 【重点】第5项检查偏移 49(最后一个数据字节)。此前 icmp_tx 存在差一错误
//        (bcnt < data_last), 会把最后1字节发成 0x00, 现已修复为 <= 。
//============================================================================
module tb_icmp;

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

    // ---- icmp_rx ----
    wire        reply_en;
    wire [15:0] icmp_id, icmp_seq, icmp_cksum, icmp_dlen;
    wire [7:0]  fifo_dout;
    wire        fifo_empty, fifo_rd;
    icmp_rx u_icmp_rx (
        .clk(clk), .rst(rst),
        .p_sof(p_sof), .p_en(p_en), .p_eof(p_eof), .p_data(p_data),
        .payload_len(payload_len), .ip_ok(ip_ok),
        .reply_en(reply_en), .id(icmp_id), .seq(icmp_seq),
        .icmp_cksum(icmp_cksum), .data_len(icmp_dlen),
        .fifo_rd(fifo_rd), .fifo_dout(fifo_dout), .fifo_empty(fifo_empty));

    // ---- icmp_tx ----
    wire        tx_req, tx_done, tx_en;
    wire [7:0]  tx_data;
    icmp_tx #(.BOARD_MAC(48'h00_11_22_33_44_55), .BOARD_IP(32'hC0A8_017B)) u_icmp_tx (
        .clk(clk), .rst(rst),
        .reply_en(reply_en), .id(icmp_id), .seq(icmp_seq),
        .icmp_cksum(icmp_cksum), .data_len(icmp_dlen),
        .dst_mac(smac), .dst_ip(src_ip),
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

    // ICMP Echo 请求帧(54字节, 含正确FCS): 数据区为 "abcdefgh"
    reg [7:0] frame [0:53];
    initial begin
        frame[0]=8'h00; frame[1]=8'h11; frame[2]=8'h22; frame[3]=8'h33;
        frame[4]=8'h44; frame[5]=8'h55; frame[6]=8'h00; frame[7]=8'h11;
        frame[8]=8'h22; frame[9]=8'h33; frame[10]=8'h44; frame[11]=8'h66;
        frame[12]=8'h08; frame[13]=8'h00; frame[14]=8'h45; frame[15]=8'h00;
        frame[16]=8'h00; frame[17]=8'h24; frame[18]=8'h00; frame[19]=8'h00;
        frame[20]=8'h40; frame[21]=8'h00; frame[22]=8'h40; frame[23]=8'h01;
        frame[24]=8'hB6; frame[25]=8'hA9; frame[26]=8'hC0; frame[27]=8'hA8;
        frame[28]=8'h01; frame[29]=8'h64; frame[30]=8'hC0; frame[31]=8'hA8;
        frame[32]=8'h01; frame[33]=8'h7B; frame[34]=8'h08; frame[35]=8'h00;
        frame[36]=8'h66; frame[37]=8'h68; frame[38]=8'h00; frame[39]=8'h01;
        frame[40]=8'h00; frame[41]=8'h01; frame[42]=8'h61; frame[43]=8'h62;
        frame[44]=8'h63; frame[45]=8'h64; frame[46]=8'h65; frame[47]=8'h66;
        frame[48]=8'h67; frame[49]=8'h68; frame[50]=8'h7C; frame[51]=8'hFE;
        frame[52]=8'h5E; frame[53]=8'h1E;
    end

    initial begin
        rst = 1; txcnt = 0; #20; rst = 0; #10;

        // 发送: 前导码 + SFD + 帧体
        // 在下降沿驱动, 避免与 DUT 上升沿采样竞争
        for (k = 0; k < 7; k = k + 1) begin @(negedge clk); d = 8'h55; dv = 1; end
        @(negedge clk); d = 8'hD5;
        for (k = 0; k < 54; k = k + 1) begin @(negedge clk); d = frame[k]; end
        @(negedge clk); dv = 0; d = 0;

        wait (tx_done == 1'b1);
        // chk 路径比 tx_en 晚 2 拍, 且 crc_ok 是单拍脉冲, 需留足时间
        #100;

        // ---- 检查项(不满足则 errors+1, 说明见注释) ----
        if (txcnt !== 54)                    errors = errors + 1;  // 应答帧应为 54 字节
        if (txbuf[34] !== 8'h00)             errors = errors + 1;  // ICMP类型应为 0(应答)
        if ({txbuf[38],txbuf[39]} !== 16'h0001) errors = errors + 1;  // ID 应为 1
        if ({txbuf[40],txbuf[41]} !== 16'h0001) errors = errors + 1;  // SEQ 应为 1
        if ({txbuf[36],txbuf[37]} !== 16'h6E68) errors = errors + 1;  // 应答校验和 = 请求0x6668+0x0800(Type 8->0修正)
        // 应答帧的IP首部校验和: 请求/应答IP头仅源目的IP互换、总长同为36, 反码和不变
        // -> 仍为 0xB6A9。此前无断言守护, 改动 ip_hdr_cksum 或IP头字段不会报警。
        if ({txbuf[24],txbuf[25]} !== 16'hB6A9) errors = errors + 1;  // 应答IP首部校验和应为 0xB6A9
        if (txbuf[42] !== 8'h61)             errors = errors + 1;  // 数据首字节应为 'a'
        if (txbuf[49] !== 8'h68)             errors = errors + 1;  // 数据末字节应为 'h'(验证边界修复)
        if ({txbuf[26],txbuf[27],txbuf[28],txbuf[29]} !== 32'hC0A8_017B)
                                             errors = errors + 1;  // 应答源IP应为本板 192.168.1.123
        if (!chk_ok_seen)                    errors = errors + 1;  // 应答帧 FCS 应校验通过

        #30;
        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_icmp: PASS ====");
        else             $display("==== tb_icmp: %0d 个错误 FAIL ====", errors);
        $finish;
    end

    // 看门狗: 若始终没等到应答(wait tx_done), 防止仿真无限运行
    initial begin
        #100000;
        $display("==== tb_icmp: 超时(未收到应答) FAIL ====");
        $finish;
    end

endmodule
