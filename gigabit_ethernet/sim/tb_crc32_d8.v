`timescale 1ns / 1ps
//============================================================================
// tb_crc32_d8 : CRC-32 模块仿真
//
// 被测模块 : rtl/common/crc32_d8.v
//
// 测试点(说明全部写在注释里, 仿真时不再逐条打印):
//   1) 标准自检 : 逐字节输入 "123456789", crc_out 应等于 0xCBF43926
//   2) 好帧     : 输入 54 字节完整帧(含正确的 FCS), 帧尾 crc_ok 应为 1
//   3) 坏帧     : 改动其中 1 字节后重发,           帧尾 crc_ok 应为 0
//
// 说明: 只在最后打印一行 PASS / FAIL
//============================================================================
module tb_crc32_d8;

    reg         clk = 0, rst = 1;
    reg  [7:0]  data = 0;
    reg         en = 0;
    wire [31:0] crc_out;
    wire        crc_ok;
    integer     errors = 0;
    integer     i;

    always #4 clk = ~clk;                       // 125MHz(周期8ns)

    crc32_d8 dut (.clk(clk), .rst(rst), .data(data),
                  .data_en(en), .crc_out(crc_out), .crc_ok(crc_ok));

    //------------------------------------------------------------------
    // 一个完整的 ICMP Echo 请求帧(54字节, 含正确的 FCS)
    //------------------------------------------------------------------
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

    reg crc_ok_latch;

    // 发送 n 个字节: 在时钟下降沿驱动数据, 上升沿被模块稳定采样(无竞争)
    task send_bytes(input integer n);
        integer k;
        begin
            en = 0; @(posedge clk);             // 间隔: 确保下一帧首字节被识别为新帧
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk); data = frame[k]; en = 1;
            end
            @(negedge clk); en = 0;             // 帧尾
            @(posedge clk);                // DUT 在该拍(active->NBA)把 crc_ok 置为单拍脉冲结果
            @(posedge clk); 
            crc_ok_latch = crc_ok;              // #1 后 NBA 已生效, 锁到有效值(勿在 NBA 前读到旧值)
        end
    endtask

    initial begin
        rst = 1; #20; rst = 0; #10;

        // ---- 1) 标准自检: CRC-32("123456789") = 0xCBF43926 ----
        @(negedge clk); data = 8'h31; en = 1;   // '1'
        @(negedge clk); data = 8'h32; en = 1;   // '2'
        @(negedge clk); data = 8'h33; en = 1;   // '3'
        @(negedge clk); data = 8'h34; en = 1;   // '4'
        @(negedge clk); data = 8'h35; en = 1;   // '5'
        @(negedge clk); data = 8'h36; en = 1;   // '6'
        @(negedge clk); data = 8'h37; en = 1;   // '7'
        @(negedge clk); data = 8'h38; en = 1;   // '8'
        @(negedge clk); data = 8'h39; en = 1;   // '9'
        @(posedge clk);                     // 采样最后一字节
        #1;
        if (crc_out !== 32'hCBF43926) errors = errors + 1;   // 自检值应为 CBF43926

        // 复位, 使好帧从初始 FFFFFFFF 开始
        rst = 1; @(posedge clk); rst = 0;

        // ---- 2) 好帧: crc_ok 应为 1 ----
        send_bytes(54);
        if (!crc_ok_latch) errors = errors + 1;               // 好帧 crc_ok 应为 1

        // ---- 3) 坏帧: 改 1 字节后 crc_ok 应为 0 ----
        frame[42] = 8'hFF;
        send_bytes(54);
        if (crc_ok_latch)  errors = errors + 1;               // 坏帧 crc_ok 应为 0, 若误判为 1 则报错

        #20;
        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_crc32_d8: PASS ====");
        else             $display("==== tb_crc32_d8: %0d 个错误 FAIL ====", errors);
        $finish;
    end

endmodule
