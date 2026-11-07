`timescale 1ns / 1ps
//============================================================================
// tb_preamble_inserter : 前导码/SFD 插入模块的单元测试
//
// 被测   : rtl/phy/preamble_inserter.v
//
// 背景   : 对照野火官方例程 udp_tx.v 的 st_preamble 状态机确认, RTL8211F 不会
//          自动产生前导码, 必须由 FPGA 补发 7x0x55 + 0xD5。本测试即验证
//          "补得对不对、有没有把原始数据搞坏或搞丢"。
//
// 测试点 :
//   1) 帧格式 : 输出前 7 字节必须是 0x55, 第 8 字节必须是 0xD5
//   2) 长度   : 输入 N 字节 -> 输出必须是 N+8 字节(不多不少)
//   3) 数据完整性: 前导码之后的数据必须与输入逐字节完全相同(不丢不乱序)
//   4) 多帧连续: 连续发两帧不同长度, 每帧都要各自独立补齐前导码
//   5) 空闲   : 无帧时 m_en 必须保持 0, 不能冒出多余字节
//
// 用法   : Vivado xsim; 项目仿真顶层仍是 tb_eth_top, 这里只做模块级
//          单元测试随 tb_*.v 一起被 tools/run_sim_no90.tcl 自动编译。
//============================================================================
module tb_preamble_inserter;

    reg         clk = 0;
    reg         rst = 1;
    reg  [7:0]  s_data = 0;      // 插入前(纯MAC帧, 从目的MAC开始)
    reg         s_en   = 0;
    wire [7:0]  m_data;          // 插入后(已带前导码)
    wire        m_en;

    always #4 clk = ~clk;        // 125MHz 周期 8ns, 与工程一致

    preamble_inserter dut (
        .clk    (clk),
        .rst    (rst),
        .s_data (s_data),
        .s_en   (s_en),
        .m_data (m_data),
        .m_en   (m_en)
    );

    reg [7:0] frame [0:127];     // 发送的原始帧数据
    reg [7:0] rxbuf [0:255];     // 采集到的输出字节
    integer   rcnt   = 0;        // 输出字节计数
    integer   errors = 0;
    integer   i;

    //--------------------------------------------------------------
    // 采集: 在时钟上升沿后稍延迟采样, 保证读到稳定的组合输出
    //--------------------------------------------------------------
    always @(posedge clk) begin
        #1;
        if (m_en) begin
            rxbuf[rcnt] = m_data;
            rcnt        = rcnt + 1;
        end
    end

    //--------------------------------------------------------------
    // 以"字节为单位"发送一帧: 数据在上升沿被采样, 故在下降沿更新
    //--------------------------------------------------------------
    task send_frame(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk);
                s_data <= frame[k];
                s_en   <= 1'b1;
            end
            @(negedge clk);
            s_data <= 8'h00;
            s_en   <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------
    // 校验: 前导码 + SFD + 数据完整性 + 总长度
    //--------------------------------------------------------------
    task check_frame(input integer n, input [8*12:1] tag);
        integer k;
        integer e;
        begin
            e = 0;
            if (rcnt !== n + 8) begin
                e = e + 1;
                $display("  [%0s] 长度错误: 实际 %0d, 期望 %0d", tag, rcnt, n + 8);
            end else begin
                for (k = 0; k < 7; k = k + 1)
                    if (rxbuf[k] !== 8'h55) begin
                        e = e + 1;
                        $display("  [%0s] 前导码[%0d] = %h, 期望 55", tag, k, rxbuf[k]);
                    end
                if (rxbuf[7] !== 8'hD5) begin
                    e = e + 1;
                    $display("  [%0s] SFD = %h, 期望 D5", tag, rxbuf[7]);
                end
                for (k = 0; k < n; k = k + 1)
                    if (rxbuf[k + 8] !== frame[k]) begin
                        e = e + 1;
                        $display("  [%0s] 数据[%0d] = %h, 期望 %h", tag, k, rxbuf[k+8], frame[k]);
                    end
            end
            errors = errors + e;
            $display("  [%0s] %s  (输入%0d字节 -> 输出%0d字节, 错误%0d)",
                     tag, (e == 0) ? "OK  " : "FAIL", n, rcnt, e);
        end
    endtask

    initial begin
        // 构造可辨识的数据图案(0,1,2,...), 便于定位错序/错位
        for (i = 0; i < 128; i = i + 1) frame[i] = i[7:0];

        rst = 1; #100;
        rst = 0; #100;

        // 空闲时不应有任何输出
        if (m_en !== 1'b0) begin
            errors = errors + 1;
            $display("  [空闲] 错误: 无帧时 m_en 不为 0");
        end
        if (rcnt !== 0) begin
            errors = errors + 1;
            $display("  [空闲] 错误: 无帧时已采集到 %0d 字节", rcnt);
        end

        // ---- 第 1 帧: 64 字节(典型 ARP 应答帧长) ----
        rcnt = 0;
        send_frame(64);
        #400;                       // 等待内部 9 级延迟线冲刷完毕
        check_frame(64, "帧1-64B");

        // ---- 第 2 帧: 不同长度(23 字节), 验证多帧都能独立补齐前导码 ----
        rcnt = 0;
        send_frame(23);
        #400;
        check_frame(23, "帧2-23B");

        // ---- 帧结束后应恢复空闲, 不再冒出字节 ----
        i = rcnt;
        #400;
        if (rcnt !== i) begin
            errors = errors + 1;
            $display("  [结束] 错误: 帧结束后仍多出 %0d 字节", rcnt - i);
        end else
            $display("  [结束] OK  : 帧结束后输出停止");

        #100;
        if (errors == 0) $display("==== tb_preamble_inserter: PASS ====");
        else             $display("==== tb_preamble_inserter: %0d 个错误 FAIL ====", errors);
        $finish;
    end

    // 看门狗
    initial begin
        #100000;
        $display("==== tb_preamble_inserter: 超时 FAIL ====");
        $finish;
    end

endmodule
