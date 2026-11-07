`timescale 1ns / 1ps
//============================================================================
// tb_rgmii : RGMII <-> GMII 双向转换仿真
//
// 被测模块 : rtl/phy/rgmii_to_gmii.v (接收), rtl/phy/gmii_to_rgmii.v (发送)
// 依赖     : sim/xilinx_prims_sim.v (IDDR/ODDR 行为模型)
//
// 测试点(说明写在注释里, 仿真时不再逐条打印):
//   RX 方向: 模拟 PHY 以 RGMII DDR 方式送出 16 个字节
//            (上升沿=低4位, 下降沿=高4位), 检查恢复出的 GMII 字节是否正确
//   TX 方向: 送入 16 个 GMII 字节, 按 RGMII 时序在上升沿取低4位、下降沿取高4位重组,
//            检查重组后的字节是否一致
//
// 说明: 本工程无 90° 采样; 改为把喂给 DUT 的 rxc 推后 2ns, 建模 PHY 内部 2ns RX 延迟
//============================================================================
module tb_rgmii;

    reg         rxc = 0, rst = 1;
    reg  [3:0]  rxd = 0;
    reg         rx_ctl = 0;

    always #4 rxc = ~rxc;                 // 125MHz RGMII 时钟
    wire        rxc_dly;                  // 推后2ns的RXC(建模PHY内部延迟)
    wire [7:0]  gmii_rxd;
    wire        gmii_rx_dv;
    integer     errors = 0;
    integer     k;

    assign #2 rxc_dly = rxc;              // 行为级建模 PHY 内部 2ns RX 延迟

    // ---- 被测: 接收方向 RGMII -> GMII ----
    // SCAN_EN=0: IDELAY tap 固定 0(直通);
    //           idelay_refclk 给 200MHz 供 IDELAYCTRL(行为模型不依赖, 仅完整连接)
    reg idelay_refclk = 0;
    always #2.5 idelay_refclk = ~idelay_refclk;   // 200MHz
    wire [4:0] dbg_tap;
    wire       dbg_tap_rdy;
    rgmii_to_gmii #(.SCAN_EN(0)) u_rx (
        .rxc(rxc_dly), .rxd(rxd), .rx_ctl(rx_ctl),
        .clk125(rxc_dly),         // 0° 主时钟取延迟后的RXC(等价PHY内部延迟后采样)
        .idelay_refclk(idelay_refclk),
        .rst(rst),
        .gmii_rxd(gmii_rxd), .gmii_rx_dv(gmii_rx_dv),
        .dbg_tap(dbg_tap), .dbg_tap_rdy(dbg_tap_rdy));

    // ---- 被测: 发送方向 GMII -> RGMII ----
    reg  [7:0]  gmii_txd = 0;
    reg         gmii_tx_en = 0;
    wire [3:0]  txd;
    wire        tx_ctl, txc;
    gmii_to_rgmii u_tx (
        .clk125(rxc), .rst(rst),
        .gmii_txd(gmii_txd), .gmii_tx_en(gmii_tx_en),
        .txd(txd), .tx_ctl(tx_ctl), .txc(txc));

    // 行为级仿真需显式例化 glbl, 供 IDDR/ODDR 的 GSR 冻结行为与真实原语一致
    // (xsim 下由 $XILINX_VIVADO 的 glbl.v 自动例化, 这里不影响)
    glbl glbl ();

    // 16 个测试字节
    reg [7:0] test [0:15];

    // ---- RX 激励: 上升沿发低4位, 下降沿发高4位 (RGMII 标准时序) ----
    task send_rgmii_byte(input [7:0] b);
        begin
            @(posedge rxc);  rxd <= b[3:0]; rx_ctl <= 1'b1;   // 上升沿: 低4位
            @(negedge rxc);  rxd <= b[7:4];                   // 下降沿: 高4位
        end
    endtask

    // ---- 采集恢复出的 GMII 字节 ----
    reg [7:0] rxout [0:15];
    integer   rcnt = 0;
    always @(posedge rxc_dly) begin
        if (gmii_rx_dv) begin
            rxout[rcnt] = gmii_rxd;
            rcnt = rcnt + 1;
        end
    end

    // ---- TX 采集: 上升沿取低4位, 下降沿取高4位, 重组字节 ----
    // 采集必须"模拟真实 PHY": 以 TXC 上升沿采到的 CTL 为准判定该字节有效;
    // 若只看下降沿的 tx_ctl, 会把 tx_ctl 刚拉高的那半个周期(此时 TXD 还是
    // 上一字节残留的低4位拼成)误采成一个字节 -> 结果整体偏移1字节
    reg [7:0] txout [0:15];
    integer   tcnt = 0;
    reg [3:0] lo_nib;
    reg       ctl_at_rise = 1'b0;              // 上升沿时刻 tx_ctl 的值
    always @(posedge rxc) begin
        #1;
        if (tx_ctl) begin
            lo_nib      = txd;                 // 上升沿: 低4位
            ctl_at_rise = 1'b1;
        end else
            ctl_at_rise = 1'b0;
    end
    always @(negedge rxc) begin
        #1;
        if (tx_ctl && ctl_at_rise) begin
            txout[tcnt] = {txd, lo_nib};       // 下降沿: 高4位, 拼成字节
            tcnt = tcnt + 1;
        end
    end

    initial begin
        // 测试数据让高4位与低4位不同(高4位=~k, 低4位=k): 这样若上升/下降沿
        // 半字节接反, 恢复出的字节会立即变成 0x1E 之类错位值, 一眼可见
        for (k = 0; k < 16; k = k + 1) test[k] = {~k[3:0], k[3:0]};   // 0xE1,0xD2,0xC3,...
        rst = 1; #20; rst = 0; #120;   // 等到 glbl.GSR 释放(默认100ns)后再发帧,
                                         // 模拟"配置完成后才来流量", 与真实硬件一致

        // ---- RX 方向 ----
        for (k = 0; k < 16; k = k + 1) send_rgmii_byte(test[k]);
        @(posedge rxc); rxd <= 0; rx_ctl <= 0;    // 帧结束
        #30;
        if (rcnt !== 16) errors = errors + 1;     // 应恢复出 16 个字节
        for (k = 0; k < 16; k = k + 1)
            if (rxout[k] !== test[k]) errors = errors + 1;   // 每个字节应与激励一致

        // ---- TX 方向 ----
        // 在下降沿驱动: gmii_to_rgmii 内有流水线寄存器(上升沿采样),
        // 若在 posedge 当拍改信号会竞争, 导致输出整体偏移1个字节
        for (k = 0; k < 16; k = k + 1) begin
            @(negedge rxc); gmii_txd = test[k]; gmii_tx_en = 1;
        end
        @(negedge rxc); gmii_txd = 0; gmii_tx_en = 0;
        #30;
        if (tcnt !== 16) errors = errors + 1;     // 应发出 16 个字节
        for (k = 0; k < 16; k = k + 1)
            if (txout[k] !== test[k]) errors = errors + 1;   // 重组后应与激励一致

        #20;
        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_rgmii: PASS ====");
        else             $display("==== tb_rgmii: %0d 个错误 FAIL ====", errors);
        $finish;
    end

    // 看门狗
    initial begin
        #100000;
        $display("==== tb_rgmii: 超时 FAIL ====");
        $finish;
    end

endmodule
