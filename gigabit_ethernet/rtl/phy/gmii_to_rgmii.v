//============================================================================
// 模块名   : gmii_to_rgmii
// 功能     : RGMII 发送转换: 把8bit GMII数据打包成4bit DDR数据发给PHY
// 原理     : 用5个ODDR原语, 在时钟上升沿输出低4位、下降沿输出高4位;
//            发送时钟TXC由FPGA自己产生并经ODDR转发给PHY(源同步发送)。
//            RGMII规定: 上升沿=数据[3:0]+DV; 下降沿=数据[7:4]+DV^ER,
//            本设计无错误帧, ER恒为0, 所以下降沿的CTL=DV。
//============================================================================
module gmii_to_rgmii(
    input  wire       clk125,     // 发送逻辑时钟(即要转发给PHY的TXC)
    input  wire       rst,
    input  wire [7:0] gmii_txd,   // GMII发送数据
    input  wire       gmii_tx_en, // GMII发送有效
    output wire [3:0] txd,        // RGMII发送数据(DDR)
    output wire       tx_ctl,     // RGMII发送控制
    output wire       txc         // 转发给PHY的发送时钟
);

    // 流水线寄存器: 让"协议栈组合逻辑 -> ODDR"变成"寄存器 -> ODDR"(亚纳秒),
    // 否则长组合路径在 RGMII TX 的半周期(4ns)要求下会时序违例。
    // 本设计 RGMII 无严格延迟要求, 多打一拍不影响功能。
    reg [7:0] txd_pipe;
    reg       txen_pipe;
    always @(posedge clk125 or posedge rst) begin
        if (rst) begin
            txd_pipe  <= 8'b0;
            txen_pipe <= 1'b0;
        end else begin
            txd_pipe  <= gmii_txd;
            txen_pipe <= gmii_tx_en;
        end
    end

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : ODDR_DATA
            // ODDR 采用 SAME_EDGE: D1/D2 同在上升沿采样, 保证输出的两个
            // 半字节来自同一个 GMII 字节。
            ODDR #(
                .DDR_CLK_EDGE("SAME_EDGE"),
                .INIT(1'b0),
                .SRTYPE("ASYNC")
            ) u_oddr_data (
                .Q  (txd[i]),
                .C  (clk125),
                .CE (1'b1),
                .D1 (txd_pipe[i]),      // 上升沿输出: 低4位
                .D2 (txd_pipe[i+4]),    // 下降沿输出: 高4位
                .R  (rst),
                .S  (1'b0)
            );
        end
    endgenerate

    // 控制信号: D1=DV(上升沿), D2=DV^ER=DV(下降沿, ER=0)
    // 同样必须用 SAME_EDGE, 与数据保持完全一致的输出时序
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("ASYNC")
    ) u_oddr_ctl (
        .Q  (tx_ctl),
        .C  (clk125),
        .CE (1'b1),
        .D1 (txen_pipe),
        .D2 (txen_pipe),
        .R  (rst),
        .S  (1'b0)
    );

    // 时钟转发: 上升沿输出1, 下降沿输出0 -> 占空比50%的输出时钟
    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("ASYNC")
    ) u_oddr_clk (
        .Q  (txc),
        .C  (clk125),
        .CE (1'b1),
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (1'b0),
        .S  (1'b0)
    );

endmodule
