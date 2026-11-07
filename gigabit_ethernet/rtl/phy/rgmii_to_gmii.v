`timescale 1ns / 1ps
//============================================================================
// 模块名   : rgmii_to_gmii
// 功能     : RGMII 接收转换: 把PHY发来的4bit DDR数据恢复成8bit GMII数据
// 原理     : RGMII在时钟上升沿传低4位(GMII字节[3:0]), 下降沿传高4位([7:4]),
//            即DDR双倍数据率。使用5个IDDR原语(SAME_EDGE_PIPELINED)在同一周期
//            同时输出两个半字节, 拼成完整字节: gmii_d={Q2,Q1}={高4位,低4位}。
//            (Q1=上升沿采到的低4位, Q2=下降沿采到的高4位)
//
// 采样时钟 : 引脚 rxc 经一级 BUFG 得到 rxc_bufg, 直接驱动 IDDR.C。
//            PHY(RTL8211F) 使能 RGMII-ID, 其 RXC 已相对 RXD 延迟 2ns。
// 相位校准 : rxd[3:0]/rx_ctl 各经一级 IDELAYE2(VAR_LOAD, 78.125ps/tap,
//            0~31 tap = 0~2.5ns), 参考时钟 idelay_refclk = 200MHz。
//            SCAN_EN=1 时内部 FSM 循环扫描 tap, 由 ILA 观察 mac_crc_ok
//            读回命中值; SCAN_EN=0 时 tap 固定为 IDELAY_TAP。
//
// 相关原语 : IDDR / 源同步时钟 / RGMII-ID / IDELAYE2 / IDELAYCTRL / BUFG
//============================================================================
module rgmii_to_gmii #(
    parameter        SCAN_EN    = 0,    // 1=上板自动扫描tap(相位校准); 0=固定IDELAY_TAP(仿真/定稿)
    parameter [4:0]  IDELAY_TAP = 5'd0, // SCAN_EN=0 时的固定延时(0~31; 1tap≈78.125ps, 32tap=2.5ns)
    parameter        DWELL_W    = 20    // 每 tap 停留 2^DWELL_W 个 clk125 周期(2^20≈8.4ms)
)(
    input  wire       rxc,           // PHY送来的接收时钟(引脚) 经BUFG后作DDR采样源
    input  wire [3:0] rxd,           // RGMII接收数据(DDR) 经IDELAYE2后进IDDR
    input  wire       rx_ctl,        // RGMII接收控制(=GMII的DV/ER组合)
    input  wire       clk125,        // 逻辑主时钟: IDDR后流水 + IDELAY扫描FSM
    input  wire       idelay_refclk, // 200MHz IDELAYCTRL 参考时钟(来自clk_gen)
    input  wire       rst,
    output wire [7:0] gmii_rxd,      // 恢复出的GMII数据
    output wire       gmii_rx_dv,    // 恢复出的GMII有效信号(DV)
    output wire       gmii_rx_er,    // 恢复出的GMII错误
    output wire [4:0] dbg_tap,       // [调试] 当前生效的IDELAY tap值(SCAN_EN扫描时可见)
    output wire       dbg_tap_rdy    // [调试] IDELAYCTRL锁定(RDY), 为0说明参考时钟没接好
);

    //------------------------------------------------------------------
    // 引脚时钟经 BUFG 后作为 DDR 采样时钟
    //------------------------------------------------------------------
    wire rxc_bufg;
    BUFG u_bufg_rxc (.I(rxc), .O(rxc_bufg));

    //==================================================================
    // IDELAYE2 可调延时与 tap 扫描
    //==================================================================
    //   数据路径: 引脚 -> IBUF -> IDELAYE2 -> IDDR.D
    //   时钟路径: 引脚 -> BUFG(rxc_bufg) -> IDDR.C
    //   扫描改变"数据相对时钟"的延时, 等效于在眼图里平移采样点,
    //   直到采样沿落回数据眼中央(SFD=D5, CRC全对)。
    //------------------------------------------------------------------
    reg  [4:0]         tap_r;      // 当前生效 tap(已载入IDELAYE2的值)
    reg                tap_ld;     // IDELAYE2 加载脉冲(VAR_LOAD: LD=1时载入CNTVALUEIN)
    reg  [DWELL_W-1:0] dwell;      // 每 tap 停留计数
    wire [4:0]         tap_next = tap_r + 5'd1;

    always @(posedge clk125 or posedge rst) begin
        if (rst) begin
            tap_r  <= 5'd0;
            tap_ld <= 1'b0;
            dwell  <= {DWELL_W{1'b0}};
        end else if (SCAN_EN) begin
            tap_ld <= 1'b0;
            dwell  <= dwell + 1'b1;
            if (&dwell) begin          // 停留时间到 -> 推进到下一 tap 并载入
                tap_r  <= tap_next;
                tap_ld <= 1'b1;
            end
        end else begin                 // 定稿模式: 常载入固定 tap
            tap_r  <= IDELAY_TAP;
            tap_ld <= 1'b1;
        end
    end

    // SCAN_EN/IDELAY_TAP 为参数, 用 generate-if 选择(Vivado 2018.3)
    wire [4:0] idel_cntvaluein;
    wire       idel_ld;
    generate
        if (SCAN_EN) begin : G_IDEL_SCAN
            assign idel_cntvaluein = tap_next;
            assign idel_ld         = tap_ld;
        end else begin : G_IDEL_FIX
            assign idel_cntvaluein = IDELAY_TAP;
            assign idel_ld         = 1'b1;
        end
    endgenerate

    wire [3:0] rxd_dly;              // 延时后的数据
    wire       ctl_dly;              // 延时后的控制

    // IODELAY_GROUP 在 IDELAYE2/IDELAYCTRL 上须以属性标注, 不能作实例参数。
    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : IDLY_DATA
            (* IODELAY_GROUP = "rgmii_rx_idelay" *) IDELAYE2 #(
                .CINVCTRL_SEL         ("FALSE"),
                .DELAY_SRC            ("IDATAIN"),
                .HIGH_PERFORMANCE_MODE("TRUE"),
                .IDELAY_TYPE          ("VAR_LOAD"),
                .IDELAY_VALUE         (0),
                .PIPE_SEL             ("FALSE"),
                .REFCLK_FREQUENCY     (200.0),       // 对应 idelay_refclk=200MHz -> 78.125ps/tap
                .SIGNAL_PATTERN       ("DATA")
            ) u_idelay (
                .C          (clk125),   // VAR_LOAD 载入时钟
                .REGRST     (1'b0),
                .LD         (idel_ld),
                .CE         (1'b0),
                .INC        (1'b0),
                .CINVCTRL   (1'b0),
                .LDPIPEEN   (1'b0),
                .CNTVALUEIN (idel_cntvaluein),
                .IDATAIN    (rxd[g]),
                .DATAIN     (1'b0),
                .DATAOUT    (rxd_dly[g])
            );
        end

        // 控制信号单独一路(必须与数据路同 tap, 否则 DV 与字节错位)
        (* IODELAY_GROUP = "rgmii_rx_idelay" *) IDELAYE2 #(
            .CINVCTRL_SEL         ("FALSE"),
            .DELAY_SRC            ("IDATAIN"),
            .HIGH_PERFORMANCE_MODE("TRUE"),
            .IDELAY_TYPE          ("VAR_LOAD"),
            .IDELAY_VALUE         (0),
            .PIPE_SEL             ("FALSE"),
            .REFCLK_FREQUENCY     (200.0),
            .SIGNAL_PATTERN       ("DATA")
        ) u_idelay_ctl (
            .C          (clk125),
            .REGRST     (1'b0),
            .LD         (idel_ld),
            .CE         (1'b0),
            .INC        (1'b0),
            .CINVCTRL   (1'b0),
            .LDPIPEEN   (1'b0),
            .CNTVALUEIN (idel_cntvaluein),
            .IDATAIN    (rx_ctl),
            .DATAIN     (1'b0),
            .DATAOUT    (ctl_dly)
        );
    endgenerate

    // IDELAYCTRL: IDELAYE2 的参考(校准 tap 延时), 必须与上面同 IODELAY_GROUP
    (* IODELAY_GROUP = "rgmii_rx_idelay" *) IDELAYCTRL u_idelayctrl (
        .REFCLK (idelay_refclk),   // 200MHz 来自 clk_gen
        .RST    (rst),
        .RDY    (dbg_tap_rdy)
    );

    assign dbg_tap = tap_r;

    //==================================================================
    // IDDR: 采样钟 = rxc_bufg, 数据 = IDELAY 后的 rxd/ctl
    //==================================================================
    // q1=上升沿采样(低半字节), q2=下降沿采样(高半字节, 对齐输出)
    wire [3:0] q1_d, q2_d;
    wire       q1_c, q2_c;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : IDDR_DATA
            IDDR #(
                .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
                .INIT_Q1(1'b0),
                .INIT_Q2(1'b0),
                .SRTYPE("ASYNC")
            ) u_iddr_data (
                .Q1 (q1_d[i]),   // 上升沿采样值(=GMII低4位)
                .Q2 (q2_d[i]),   // 下降沿采样值(=GMII高4位), 对齐输出
                .C  (rxc_bufg),  // 用引脚时钟采样
                .CE (1'b1),
                .D  (rxd_dly[i]),// 经IDELAYE2延时后的数据
                .R  (1'b0),
                .S  (1'b0)
            );
        end
    endgenerate

    // 控制信号单独一路IDDR
    IDDR #(
        .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
        .INIT_Q1(1'b0),
        .INIT_Q2(1'b0),
        .SRTYPE("ASYNC")
    ) u_iddr_ctl (
        .Q1 (q1_c),
        .Q2 (q2_c),
        .C  (rxc_bufg),  // 与数据路同源同相, 保证 DV 与字节不错位
        .CE (1'b1),
        .D  (ctl_dly),   // 经IDELAYE2延时后的控制
        .R  (1'b0),
        .S  (1'b0)
    );

    // IDDR 输出位于 rxc_bufg 域, 这里用 clk125 打两拍流水:
    //   - 两时钟同源同频(均派生自 eth_rxc), Vivado 自动做相关时钟时序分析,
    //     无需手工加跨时钟约束;
    //   - Q1/Q2 在同一拍给出且稳定维持一整个周期, 只要满足建立保持时间,
    //     移到 clk125 域不会破坏半字节配对。
    // 注: 变量名 _h 存的是上升沿(低4位)、_l 存的是下降沿(高4位), 命名与
    //     实际含义相反是历史遗留, 仅为可读性, 不影响功能。
    // q1组: {CTL上升沿, 低4位}; q2组: {CTL下降沿, 高4位}
    reg [4:0] sync1_h, sync2_h;
    reg [4:0] sync1_l, sync2_l;
    always @(posedge clk125 or posedge rst) begin
        if (rst) begin
            sync1_h <= 5'b0;  sync2_h <= 5'b0;
            sync1_l <= 5'b0;  sync2_l <= 5'b0;
        end else begin
            sync1_h <= {q1_c, q1_d};   // 上升沿采样值(=GMII低4位)
            sync2_h <= sync1_h;
            sync1_l <= {q2_c, q2_d};   // 下降沿采样值(=GMII高4位)
            sync2_l <= sync1_l;
        end
    end

    // 拼字节: {高4位(q2), 低4位(q1)}
    assign gmii_rxd   = {sync2_l[3:0], sync2_h[3:0]};
    assign gmii_rx_dv = sync2_h[4];
    // RX_ER: RGMII规定 RX_CTL 上升沿=DV, 下降沿=DV^ER; 仅 DV 有效时 ER 有意义。
    //   => ER = DV & (DV ^ (DV^ER)) = q1_c & ~q2_c
    assign gmii_rx_er = sync2_h[4] & ~sync2_l[4];

endmodule
