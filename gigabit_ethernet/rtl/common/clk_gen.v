`timescale 1ns / 1ps
//============================================================================
// 模块名   : clk_gen
// 作者     : hukuan
// 功能     : 用 MMCM 原语产生 RGMII 所需的时钟
//            输入  : eth_rxc   (PHY 提供的 RGMII 接收时钟, 125MHz)
//            输出  : gmii_clk      (0度,   逻辑主时钟 / 发送时钟源)
//                    idelay_refclk (200MHz, IDELAYCTRL 参考时钟)
//                     locked       (PLL 锁定指示)
//            注    : RX 采样使用引脚时钟经一级 BUFG 得到的 rxc_bufg
//                    (见 rgmii_to_gmii), 不取自 MMCM 输出。
// 说明     : 取代 Vivado "Clocking Wizard" IP(clk_wiz_0), 采用 MMCME2_BASE
//            原语 + BUFG, 无需生成 .xci 文件, 工程可直接综合/实现/仿真。
// 适用器件 : Xilinx 7 系列 (Artix-7)。其它系列请改对应 MMCM/PLL 原语。
//============================================================================
module clk_gen #(
    parameter real CLKIN_PERIOD = 8.0   // 输入时钟周期(ns): 125MHz -> 8.0
)(
    input  wire eth_rxc,
    output wire gmii_clk,
    output wire idelay_refclk,          // 200MHz, 供 IDELAYCTRL 校准 IDELAY tap
    output wire locked
);

    wire       eth_rxc_bufg; // 经 BUFG 后的全局时钟(输入脚可能不是 CC 脚)
    wire       mmcm_clk0;   // 0度, 125MHz
    wire       mmcm_clk1;   // 200MHz, IDELAY 参考
    wire       mmcm_fb;      // 反馈

    // 升腾Pro 的 RGMII RXC(C18) 落在普通 IO 而非 CC 脚, 必须先用 BUFG
    // 接到全局时钟网络, 才能驱动 MMCM。
    BUFG u_buf_in (.I(eth_rxc), .O(eth_rxc_bufg));

    // VCO = CLKIN(125MHz) * CLKFBOUT_MULT_F(8) = 1000MHz (合法范围 600~1200MHz)
    // CLKOUT0 = VCO / 8 = 125MHz, 相位 0 (逻辑主时钟: 逻辑+发送)
    // CLKOUT1 = VCO / 5 = 200MHz, 供 IDELAYCTRL 作参考时钟, 决定 IDELAY
    //           tap 精度 1/(32*2*200MHz)=78.125ps; 要求 200MHz±10MHz(UG471)
    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (8.0),
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (CLKIN_PERIOD),
        .DIVCLK_DIVIDE      (1),
        .CLKOUT0_DIVIDE_F   (8.0),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT1_DIVIDE     (5),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1  (eth_rxc_bufg),
        .CLKFBIN  (mmcm_fb),
        .CLKFBOUT (mmcm_fb),
        .CLKOUT0  (mmcm_clk0),
        .CLKOUT1  (mmcm_clk1),   // 200MHz, 供 IDELAYCTRL
        .LOCKED   (locked),
        .RST      (1'b0),
        .PWRDWN   (1'b0)
    );

    // 输出需经 BUFG 才能扇出到全局时钟网络
    BUFG u_buf0 (.I(mmcm_clk0), .O(gmii_clk));
    BUFG u_buf1 (.I(mmcm_clk1), .O(idelay_refclk));

endmodule
