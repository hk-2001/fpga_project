`timescale 1ns / 1ps
//============================================================================
// tb_mac_rx : MAC 层接收模块仿真
//
// 被测模块 : rtl/mac/mac_rx.v  (内含 crc32_d8)
//
// 测试点(说明写在注释里, 不再逐条打印):
//   1) 帧定界 : 前导码 7×0x55 + SFD 0xD5 之后才是帧的第 0 字节
//   2) 头提取 : 目的MAC / 源MAC / EtherType 是否正确
//   3) CRC    : 整帧(含FCS)送完后 crc_ok 是否为 1
//
// 激励格式 : 7字节前导码 -> 1字节SFD(0xD5) -> 54字节帧(含FCS) -> dv拉低
//============================================================================
module tb_mac_rx;

    reg         clk = 0, rst = 1;
    reg  [7:0]  d = 0;
    reg         dv = 0;
    wire        sof, en, eof, crc_ok;
    wire [7:0]  data;
    wire [47:0] dmac, smac;
    wire [15:0] etype;
    integer     errors = 0;
    integer     k;

    always #4 clk = ~clk;

    // crc_ok 是"单拍脉冲", 用锁存器记录, 避免固定等待若干拍后错过它
    reg crc_ok_seen = 1'b0;
    always @(posedge clk) if (crc_ok) crc_ok_seen <= 1'b1;

    mac_rx dut (.clk(clk), .rst(rst), .gmii_d(d), .gmii_dv(dv), .gmii_rx_er(1'b0),
        .sof(sof), .data(data), .en(en), .eof(eof),
        .dst_mac(dmac), .src_mac(smac), .eth_type(etype), .crc_ok(crc_ok));

    // 一帧完整的 ICMP Echo 请求帧(54字节, 含正确FCS)
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

    // 发送一帧: 前导码 + SFD + 帧体
    task send_frame;
        integer k;
        begin
            for (k = 0; k < 7; k = k + 1) begin
                @(negedge clk); d = 8'h55; dv = 1;   // 前导码
            end
            @(negedge clk); d = 8'hD5;               // SFD
            for (k = 0; k < 54; k = k + 1) begin
                @(negedge clk); d = frame[k];        // 帧体
            end
            @(negedge clk); dv = 0; d = 0;           // 帧结束
        end
    endtask

    initial begin
        rst = 1; #20; rst = 0; #10;

        send_frame;

        // 等 crc_ok 脉冲出现(由锁存器捕获), 再等一拍让头部字段稳定
        wait (crc_ok_seen);
        @(posedge clk);

        // ---- 检查项(不满足则 errors+1, 说明见注释) ----
        if (dmac  !== 48'h00_11_22_33_44_55) errors = errors + 1;  // 目的MAC应为 00:11:22:33:44:55
        if (smac  !== 48'h00_11_22_33_44_66) errors = errors + 1;  // 源MAC应为   00:11:22:33:44:66
        if (etype !== 16'h0800)               errors = errors + 1;  // EtherType 应为 IPv4(0x0800)
        if (!crc_ok_seen)                     errors = errors + 1;  // 好帧 crc_ok 应为 1

        #30;
        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_mac_rx: PASS ====");
        else             $display("==== tb_mac_rx: %0d 个错误 FAIL ====", errors);
        $finish;
    end

endmodule
