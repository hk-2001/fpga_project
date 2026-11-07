`timescale 1ns / 1ps
//============================================================================
// tb_tx_arbiter : 发送仲裁器仿真
//
// 被测模块 : rtl/arbiter/tx_arbiter.v
//
// 测试点(说明写在注释里, 不再逐条打印):
//   1) ICMP 与 UDP 同时请求 -> ICMP 先占用(ICMP 优先级高于 UDP)
//   2) ICMP 发完后          -> UDP 接着占用
//   3) ARP 与 UDP 同时请求  -> ARP 先占用(ARP 优先级最高)
//   4) ARP 发完后           -> UDP 接着占用
//   期望总线占用顺序: ICMP -> UDP -> ARP -> UDP
//
// 方法: 用 3 个"行为级假客户端", 获得授权后各发 4 个字节, 发完拉 done 释放
//============================================================================
module tb_tx_arbiter;

    reg clk = 0, rst = 1;
    reg  a_req = 0, i_req = 0, u_req = 0;
    wire a_gnt, i_gnt, u_gnt;
    wire [7:0] tx_data;
    wire tx_en;
    integer errors = 0;

    // 假客户端状态
    reg a_done = 0, i_done = 0, u_done = 0;
    reg [7:0] a_cnt = 0, i_cnt = 0, u_cnt = 0;

    tx_arbiter dut (
        .clk(clk), .rst(rst),
        .arp_req(a_req), .arp_done(a_done), .arp_data(8'hA0+a_cnt), .arp_en(a_gnt),
        .icmp_req(i_req), .icmp_done(i_done), .icmp_data(8'h50+i_cnt), .icmp_en(i_gnt),
        .udp_req(u_req), .udp_done(u_done), .udp_data(8'h60+u_cnt), .udp_en(u_gnt),
        .arp_gnt(a_gnt), .icmp_gnt(i_gnt), .udp_gnt(u_gnt),
        .tx_data(tx_data), .tx_en(tx_en));

    always #4 clk = ~clk;

    // 假客户端行为: 授权后数 4 拍, 然后拉 done 并撤请求
    always @(posedge clk) begin
        a_done <= 0; i_done <= 0; u_done <= 0;
        if (a_gnt) begin
            if (a_cnt == 3) begin a_cnt <= 0; a_done <= 1; a_req <= 0; end
            else a_cnt <= a_cnt + 1;
        end
        if (i_gnt) begin
            if (i_cnt == 3) begin i_cnt <= 0; i_done <= 1; i_req <= 0; end
            else i_cnt <= i_cnt + 1;
        end
        if (u_gnt) begin
            if (u_cnt == 3) begin u_cnt <= 0; u_done <= 1; u_req <= 0; end
            else u_cnt <= u_cnt + 1;
        end
    end

    // 记录总线占用者变化序列
    reg [2:0] seq [0:15];
    integer   scnt = 0;
    reg [2:0] last_owner = 0;
    always @(posedge clk) begin
        if (tx_en) begin
            if ({a_gnt,i_gnt,u_gnt} !== 3'b000 && {a_gnt,i_gnt,u_gnt} != last_owner) begin
                last_owner = {a_gnt,i_gnt,u_gnt};
                seq[scnt]  = {a_gnt,i_gnt,u_gnt};
                scnt       = scnt + 1;
            end
        end
    end

    initial begin
        rst = 1; #20; rst = 0; #10;

        // ICMP 与 UDP 同时请求 -> ICMP 应先
        i_req = 1; u_req = 1;
        wait (scnt >= 1 && i_req == 0 && u_req == 0);
        #50;

        // ARP 与 UDP 同时请求 -> ARP 应先
        a_req = 1; u_req = 1;
        wait (a_req == 0 && u_req == 0);
        #50;

        // ---- 检查项(说明见注释) ----
        if (scnt   !== 4)     errors = errors + 1;   // 共应有 4 次总线占用
        if (seq[0] !== 3'b010) errors = errors + 1;   // 第1次应为 ICMP(优先级高于UDP)
        if (seq[1] !== 3'b001) errors = errors + 1;   // 第2次应为 UDP
        if (seq[2] !== 3'b100) errors = errors + 1;   // 第3次应为 ARP(优先级最高)
        if (seq[3] !== 3'b001) errors = errors + 1;   // 第4次应为 UDP

        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_tx_arbiter: PASS ====");
        else             $display("==== tb_tx_arbiter: %0d 个错误 FAIL ====", errors);
        $finish;
    end

endmodule
