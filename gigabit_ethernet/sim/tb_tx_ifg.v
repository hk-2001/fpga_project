`timescale 1ns / 1ps
//============================================================================
// tb_tx_ifg : 帧间隔(IFG)与"背靠背两帧"的单元测试
//
// 被测   : rtl/arbiter/tx_arbiter.v  +  rtl/phy/preamble_inserter.v
//          (即"发送调度 + 帧格式封装"这一整条链)
//
// 对应问题: 帧间隔 IFG 未保证
//
// 为什么要专门测:
//   单个 ping/ARP 的间隔是毫秒级, 永远碰不到问题。只有当"第一帧还在发,
//   第二帧的请求已经排队"时才会出现背靠背, 而前导码模块内部有 9 级延迟线,
//   一帧结束后还要连续 8 拍冲刷尾部(FCS)。若新帧来得太早, 前导码会抢占输出,
//   把上一帧尾部顶掉 -> 发出没有 FCS 的残帧。这比"仅仅不合协议"严重得多。
//
// 测试点 :
//   1) 背靠背两帧必须各自完整: 长度分别为 LEN+8, 数据逐字节正确(不丢尾巴)
//   2) 两帧之间线上空闲必须 >= 12 拍(802.3 的 IFG 要求)
//   3) 每帧前 8 字节必须是 7x0x55 + 0xD5
//
// 说明: 为使测试可控, 这里定义了一个简易的 dummy_tx 作为"假的上层发送源",
//     其行为模仿真实 arp_tx/icmp_tx(请求->等授权->按字节发->发完给 done)。
//============================================================================
module tb_tx_ifg;

    reg clk = 0;
    reg rst = 1;
    always #4 clk = ~clk;             // 125MHz

    wire        arp_req,  arp_done,  arp_en;
    wire [7:0]  arp_data;
    wire        icmp_req, icmp_done, icmp_en;
    wire [7:0]  icmp_data;
    wire        arp_gnt, icmp_gnt, udp_gnt;
    wire [7:0]  arb_data;             // 仲裁器输出(插入前)
    wire        arb_en;
    wire [7:0]  phy_data;             // 前导码模块输出(线上字节流)
    wire        phy_en;

    reg start_arp  = 0;
    reg start_icmp = 0;

    // 两个"假的上层发送源": ARP 发 64 字节, ICMP 发 54 字节
    dummy_tx #(.LEN(64), .BASE(8'h10)) u_arp_src (
        .clk(clk), .rst(rst), .start(start_arp),
        .req(arp_req), .grant(arp_gnt), .done(arp_done),
        .en(arp_en), .data(arp_data));

    dummy_tx #(.LEN(54), .BASE(8'h40)) u_icmp_src (
        .clk(clk), .rst(rst), .start(start_icmp),
        .req(icmp_req), .grant(icmp_gnt), .done(icmp_done),
        .en(icmp_en), .data(icmp_data));

    tx_arbiter u_arbiter (
        .clk(clk), .rst(rst),
        .arp_req(arp_req),   .arp_done(arp_done),
        .arp_data(arp_data), .arp_en(arp_en),
        .icmp_req(icmp_req), .icmp_done(icmp_done),
        .icmp_data(icmp_data), .icmp_en(icmp_en),
        .udp_req(1'b0), .udp_done(1'b0),
        .udp_data(8'h00), .udp_en(1'b0),
        .arp_gnt(arp_gnt), .icmp_gnt(icmp_gnt), .udp_gnt(udp_gnt),
        .tx_data(arb_data), .tx_en(arb_en));

    preamble_inserter u_preamble (
        .clk(clk), .rst(rst),
        .s_data(arb_data), .s_en(arb_en),
        .m_data(phy_data), .m_en(phy_en));

    //-------------------- 采集与间隔测量 --------------------
    reg [7:0] rxbuf [0:511];
    integer   rcnt    = 0;
    integer   errors  = 0;
    integer   gap_min = 9999;     // 记录最小的帧间空闲
    integer   t_prev  = 0;
    integer   t_now;
    integer   gap;

    always @(posedge clk) begin
        #1;
        if (phy_en) begin
            t_now = $time;
            if (rcnt > 0) begin
                gap = (t_now - t_prev) / 8 - 1;    // 换算成"空闲了几拍"
                if (gap > 0) begin
                    if (gap < 12) begin
                        errors = errors + 1;
                        $display("  [IFG] 违例: 帧间仅空闲 %0d 拍(需 >=12)", gap);
                    end
                    if (gap < gap_min) gap_min = gap;
                end
            end
            rxbuf[rcnt] = phy_data;
            rcnt        = rcnt + 1;
            t_prev      = t_now;
        end
    end

    integer i;

    //-------------------- 校验一帧 --------------------
    task check_frame(input integer off, input integer len, input integer base, input [8*8:1] tag);
        integer k, e;
        begin
            e = 0;
            for (k = 0; k < 7; k = k + 1)
                if (rxbuf[off+k] !== 8'h55) begin
                    e = e + 1; $display("  [%0s] 前导码[%0d]=%h", tag, k, rxbuf[off+k]); end
            if (rxbuf[off+7] !== 8'hD5) begin
                e = e + 1; $display("  [%0s] SFD=%h", tag, rxbuf[off+7]); end
            for (k = 0; k < len; k = k + 1)
                if (rxbuf[off+8+k] !== ((base + k) & 8'hFF)) begin
                    e = e + 1;
                    $display("  [%0s] 数据[%0d]=%h 期望%h", tag, k, rxbuf[off+8+k], (base+k)&8'hFF);
                end
            errors = errors + e;
            $display("  [%0s] %s (含前导码共 %0d 字节)", tag, (e==0)?"OK  ":"FAIL", len+8);
        end
    endtask

    initial begin
        rst = 1; #100; rst = 0; #100;

        // 制造"背靠背": 先启动 ARP; 在它发送过程中再启动 ICMP, 使 ICMP 排队等待,
        // 这样 ARP 一结束仲裁器就会立刻授权 ICMP —— 正是最容易出问题的情形。
        @(negedge clk); start_arp  <= 1'b1;
        @(negedge clk); start_arp  <= 1'b0;
        #80;
        @(negedge clk); start_icmp <= 1'b1;
        @(negedge clk); start_icmp <= 1'b0;

        #6000;

        // ---- 结论 ----
        if (rcnt !== 72 + 62) begin
            errors = errors + 1;
            $display("  [总长] 错误: 采集 %0d 字节, 期望 %0d(72+62) —— 若有帧被截断会在此暴露",
                     rcnt, 72 + 62);
        end else
            $display("  [总长] OK  : 两帧完整, 共 %0d 字节", rcnt);

        check_frame(0,  64, 8'h10, "ARP-64B");
        check_frame(72, 54, 8'h40, "ICMP-54B");

        if (gap_min == 9999)
            $display("  [IFG] 提示: 未检测到帧间空隙(可能两帧未被分开)");
        else
            $display("  [IFG] 最小帧间空闲 = %0d 拍 (要求 >=12)", gap_min);

        #100;
        if (errors == 0) $display("==== tb_tx_ifg: PASS ====");
        else             $display("==== tb_tx_ifg: %0d 个错误 FAIL ====", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("==== tb_tx_ifg: 超时 FAIL ====");
        $finish;
    end

endmodule


//============================================================================
// dummy_tx : 简易"上层发送源", 行为模仿真实 arp_tx / icmp_tx
//   请求(start) -> 等授权(grant) -> 按字节发送 -> 发完给单拍 done
//   仅用于本测试文件, 不参与综合。
//============================================================================
module dummy_tx #(
    parameter LEN  = 64,
    parameter BASE = 8'h00
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    output reg        req,
    input  wire       grant,
    output reg        done,
    output reg        en,
    output reg  [7:0] data
);

    localparam S_IDLE = 2'd0, S_WAIT = 2'd1, S_SEND = 2'd2;

    reg [1:0]  state;
    reg [10:0] bcnt;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; req <= 1'b0; done <= 1'b0;
            en <= 1'b0; bcnt <= 11'd0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                            req   <= 1'b1;
                            state <= S_WAIT;
                        end
                S_WAIT: if (grant) begin
                            bcnt  <= 11'd0;
                            en    <= 1'b1;
                            state <= S_SEND;
                        end
                S_SEND: begin
                            if (bcnt == LEN - 1) begin
                                en    <= 1'b0;
                                done  <= 1'b1;
                                req   <= 1'b0;
                                state <= S_IDLE;
                            end else
                                bcnt  <= bcnt + 11'd1;
                        end
                default: state <= S_IDLE;
            endcase
        end
    end

    always @(*) data = (BASE + bcnt[7:0]);

endmodule
