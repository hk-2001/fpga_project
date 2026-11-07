`timescale 1ns / 1ps
//============================================================================
// tb_sync_fifo : 同步 FIFO 功能仿真
//
// 被测模块 : rtl/common/sync_fifo.v  (纯 RTL 同步 FIFO, FWFT 首字直通)
//            注: 早期该模块被归档在 rtl/unused/unused_modules.v, 该副本已删除;
//                现以 rtl/common/sync_fifo.v 为准(tools/run_sim.ps1 亦编译此文件)。
//
// 测试点(说明写在注释里, 不再逐条打印):
//   1) 连续写入 3 个数据 -> count=3, 且不为空
//   2) FWFT 读出顺序     -> 依次 A1, B2, C3 (队首数据始终出现在 dout 上)
//   3) 读空             -> 读完 3 个后 empty=1
//   4) clr 清空          -> 写入后拉 clr, 应立即为空
//
// 激励一律在"时钟下降沿"驱动, 让信号在上升沿被采样前已稳定,
//         避免在 posedge 当拍改信号造成的仿真竞争(会误判为功能错误)。
//============================================================================
module tb_sync_fifo;

    reg         clk = 0, rst = 1, clr = 0;
    reg         wr_en = 0, rd_en = 0;
    reg  [7:0]  din = 0;
    wire [7:0]  dout;
    wire        full, empty;
    wire [10:0] count;
    integer     errors = 0;

    always #5 clk = ~clk;                       // 100MHz(仿真用)

    sync_fifo #(.DATA_W(8), .DEPTH(1024)) dut (
        .clk(clk), .rst(rst), .clr(clr),
        .wr_en(wr_en), .din(din),
        .rd_en(rd_en), .dout(dout),
        .full(full), .empty(empty), .count(count)
    );

    // 读一拍: 下降沿置起 rd_en -> 上升沿完成读 -> 下一个下降沿撤掉
    task do_read;
        begin
            @(negedge clk); rd_en = 1;
            @(posedge clk); #1;
            @(negedge clk); rd_en = 0;
        end
    endtask

    initial begin
        // ---- 复位 ----
        rst = 1; #20; rst = 0; #10;

        // ---- 1) 写入 3 个数据(A1/B2/C3) ----
        @(negedge clk); wr_en = 1; din = 8'hA1;
        @(negedge clk);            din = 8'hB2;
        @(negedge clk);            din = 8'hC3;
        @(negedge clk); wr_en = 0;
        @(posedge clk); #1;
        if (count !== 11'd3) errors = errors + 1;   // 写入3个后 count 应为 3
        if (empty)           errors = errors + 1;   // 此时不应为空

        // ---- 2) FWFT 顺序读出 ----
        if (dout !== 8'hA1) errors = errors + 1;    // 队首应为 A1
        do_read;
        if (dout !== 8'hB2) errors = errors + 1;    // 读走A1后队首为 B2
        do_read;
        if (dout !== 8'hC3) errors = errors + 1;    // 读走B2后队首为 C3
        do_read;
        #1;
        if (!empty)          errors = errors + 1;   // 读完 3 个后应为空

        // ---- 3) clr 清空 ----
        @(negedge clk); wr_en = 1; din = 8'hD4;
        @(posedge clk); #1;
        @(negedge clk); wr_en = 0; clr = 1;
        @(posedge clk); #1;
        @(negedge clk); clr = 0;
        #1;
        if (!empty)          errors = errors + 1;   // clr 后应立即为空

        #20;
        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_sync_fifo: PASS ====");
        else             $display("==== tb_sync_fifo: %0d 个错误 FAIL ====", errors);
        $finish;
    end

endmodule
