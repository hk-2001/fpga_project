`timescale 1ns / 1ps
//============================================================================
// tb_ip_rx : IP 层接收模块仿真 (mac_rx + ip_rx 串联)
//
// 被测模块 : rtl/mac/mac_rx.v, rtl/ip/ip_rx.v
//
// 测试点(说明写在注释里, 不再逐条打印):
//   1) 协议号     : protocol 应为 1(ICMP)
//   2) 源 IP      : 应为 192.168.1.100
//   3) 载荷长度   : payload_len = IP总长度36 - 首部20 = 16
//   4) ip_ok      : CRC + 首部校验和 + 目的IP 全部通过才为 1
//   5) 载荷字节数 : 应输出 16 个字节
//   6) 载荷内容   : 首字节 0x08(ICMP type=8 请求), 第9字节 'a'(数据区开始)
//
// 说明: 本帧 IP 总长度 = 0x0024 = 36 -> 载荷 = 36-20 = 16 字节
//       载荷区间 = 帧偏移 34 ~ 49 (即 13 + total_len)
//============================================================================
module tb_ip_rx;

    reg         clk = 0, rst = 1;
    reg  [7:0]  d = 0;
    reg         dv = 0;
    integer     errors = 0;
    integer     k;

    always #4 clk = ~clk;                 // 125MHz 时钟(必须有, 否则仿真空跑)

    wire        sof, en, eof, crc_ok;
    wire [7:0]  data;
    wire [47:0] dmac, smac;
    wire [15:0] etype;
    mac_rx u_mac (.clk(clk), .rst(rst), .gmii_d(d), .gmii_dv(dv), .gmii_rx_er(1'b0),
        .sof(sof), .data(data), .en(en), .eof(eof),
        .dst_mac(dmac), .src_mac(smac), .eth_type(etype), .crc_ok(crc_ok));

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

    // ICMP Echo 请求帧(54字节, 含正确FCS)
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

    // ip_ok 是"单拍脉冲"(因为 crc_ok 是单拍脉冲), 用锁存器记录以免错过
    reg ip_ok_seen = 1'b0;
    always @(posedge clk) if (ip_ok) ip_ok_seen <= 1'b1;

    // 收集 ip_rx 输出的载荷字节
    reg [7:0] pbuf [0:31];
    integer   pcnt;
    always @(posedge clk) begin
        if (p_en) begin
            pbuf[pcnt] = p_data;
            pcnt = pcnt + 1;
        end
    end

    initial begin
        rst = 1; pcnt = 0; #20; rst = 0; #10;

        // 发送: 前导码 + SFD + 帧体
        // 必须在"下降沿"驱动: 若在 posedge 当拍改信号, 会与 DUT 的上升沿
        // 采样产生仿真竞争, 导致结果随机错误(这是仿真激励的经典坑)。
        for (k = 0; k < 7; k = k + 1) begin @(negedge clk); d = 8'h55; dv = 1; end
        @(negedge clk); d = 8'hD5;
        for (k = 0; k < 54; k = k + 1) begin @(negedge clk); d = frame[k]; end
        @(negedge clk); dv = 0; d = 0;
        // 帧尾后需要等待: mac_rx 产生 eof -> crc_ok(1拍) -> ip_rx 产生 ip_ok(1拍)
        // 共约 4 个时钟周期(32ns), 等太短会误判 ip_ok 失败
        #300;

        // ---- 检查项(不满足则 errors+1, 说明见注释) ----
        if (protocol    !== 8'h01)       errors = errors + 1;  // 协议号应为 1(ICMP)
        if (src_ip      !== 32'hC0A8_0164) errors = errors + 1;  // 源IP应为 192.168.1.100
        if (payload_len !== 16'd16)      errors = errors + 1;  // 载荷长度应为 16
        if (!ip_ok_seen)                 errors = errors + 1;  // ip_ok 应为 1(CRC+校验和+目的IP)
        if (pcnt        !== 16)          errors = errors + 1;  // 应输出 16 个载荷字节
        if (pbuf[0]     !== 8'h08)       errors = errors + 1;  // 载荷首字节 0x08 = ICMP Echo请求
        if (pbuf[8]     !== 8'h61)       errors = errors + 1;  // 第9字节 'a' = 数据区开始

        #20;
        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_ip_rx: PASS ====");
        else             $display("==== tb_ip_rx: %0d 个错误 FAIL ====", errors);
        $finish;
    end

endmodule
