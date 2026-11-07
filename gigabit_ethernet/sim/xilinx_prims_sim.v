//============================================================================
// xilinx_prims_sim.v : 仅供仿真使用的 Xilinx 原语"行为级模型"
//
// 为什么需要它:
//   rtl/phy/*.v 与 rtl/common/clk_gen.v 里直接例化了 IDDR / ODDR / BUFG /
//   MMCME2_BASE 这些 Xilinx 器件原语。iverilog 等通用仿真器没有这些库,
//   不提供模型就无法仿真。这里用最简洁的行为描述等效替代,
//   只用于功能仿真(验证逻辑与时序关系), 不参与 Vivado 综合。
//
// 说明: 该模型位于 sim/ 目录, build_vivado.tcl 只把 rtl/ 加入综合,
//       因此绝不会影响综合与实现结果。
//============================================================================

`timescale 1ns / 1ps

//----------------------------------------------------------------------------
// IDDR : 双沿输入寄存器 (DDR -> SDR)
//   本工程使用 SAME_EDGE_PIPELINED 模式:
//     - 上升沿采到的数据 -> Q1 (低半字节)
//     - 下降沿采到的数据 -> Q2 (高半字节)
//     - 两者在"下一个上升沿"同时更新, 因此同一个时钟周期内的
//       {Q2, Q1} 正好拼成一个完整字节(不会错配半个周期)
//----------------------------------------------------------------------------
module IDDR #(
    parameter DDR_CLK_EDGE = "OPPOSITE_EDGE",
    parameter INIT_Q1      = 1'b0,
    parameter INIT_Q2      = 1'b0,
    parameter SRTYPE       = "SYNC"
)(
    output Q1,
    output Q2,
    input  C,
    input  CE,
    input  D,
    input  R,
    input  S
);
    reg rise_r = INIT_Q1;   // 上升沿采样值
    reg fall_r = INIT_Q2;   // 下降沿采样值
    reg q1_r   = INIT_Q1;
    reg q2_r   = INIT_Q2;

    // 上电全局复位 GSR: 在 glbl 释放 GSR 之前, 把输出冻结在 INIT。
    // 模拟真实 UNISIM 原语行为, 使行为级模型与 xsim(真实原语) 一致 ——
    // 若仿真在 GSR 释放前(默认 100ns)就发帧, 前若干字节会被"冻掉",
    // 从而暴露"行为级 PASS、xsim FAIL"这类不一致。
    // 使用层级引用 glbl.GSR; 因此编译这个模型的 testbench 都需例化 glbl(见各 tb)。
    wire gsr = glbl.GSR;

    always @(posedge C) if (CE) rise_r <= D;   // 上升沿采 D
    always @(negedge C) if (CE) fall_r <= D;   // 下降沿采 D

    // 再打一拍: 使 Q1/Q2 在同一个上升沿对齐输出(这就是 PIPELINED 的含义)
    always @(posedge C) begin
        if (R || gsr) begin q1_r <= INIT_Q1; q2_r <= INIT_Q2; end
        else if (S)    begin q1_r <= 1'b1;   q2_r <= 1'b1;   end
        else           begin q1_r <= rise_r;  q2_r <= fall_r;  end
    end

    assign Q1 = q1_r;
    assign Q2 = q2_r;
endmodule

//----------------------------------------------------------------------------
// ODDR : 双沿输出寄存器 (SDR -> DDR)
//   本工程使用 OPPOSITE_EDGE 模式:
//     - 上升沿输出 D1 (低半字节)
//     - 下降沿输出 D2 (高半字节)
//   时钟转发用法: D1=1, D2=0 -> 输出占空比50%的时钟
//----------------------------------------------------------------------------
module ODDR #(
    parameter DDR_CLK_EDGE = "OPPOSITE_EDGE",
    parameter INIT         = 1'b0,
    parameter SRTYPE       = "SYNC"
)(
    output Q,
    input  C,
    input  CE,
    input  D1,
    input  D2,
    input  R,
    input  S
);
    reg q_r  = INIT;      // OPPOSITE_EDGE 用
    reg d1_r = INIT;      // SAME_EDGE 用: 上升沿采到的 D1
    reg d2_r = INIT;      // SAME_EDGE 用: 上升沿采到的 D2
    reg phase = 1'b0;     // 0=前半周期(上升沿之后), 1=后半周期(下降沿之后)

    // 上电全局复位 GSR: GSR 释放前冻结输出(同 IDDR 说明)
    wire gsr = glbl.GSR;

    // D1/D2 都在上升沿采样(SAME_EDGE 的关键: 两个半字节来自同一时刻)
    always @(posedge C) if (CE) begin
        d1_r <= R ? 1'b0 : (S ? 1'b1 : D1);
        d2_r <= R ? 1'b0 : (S ? 1'b1 : D2);
    end

    always @(posedge C) phase <= 1'b0;
    always @(negedge C) phase <= 1'b1;

    generate
        if (DDR_CLK_EDGE == "OPPOSITE_EDGE") begin : gen_opp
            // D1 在上升沿输出, D2 在下降沿输出(各自取当前值, 可能属于不同字节)
            always @(posedge C) if (CE) q_r <= (R || gsr) ? INIT : (S ? 1'b1 : D1);
            always @(negedge C) if (CE) q_r <= (R || gsr) ? INIT : (S ? 1'b1 : D2);
            assign Q = q_r;
        end else begin : gen_same
            // SAME_EDGE: 两个半字节都来自同一个上升沿采到的字, 保证不错位
            assign Q = (gsr || R) ? INIT : (phase ? d2_r : d1_r);
        end
    endgenerate
endmodule

//----------------------------------------------------------------------------
// BUFG : 全局时钟缓冲 (仿真中简化为一根带很小延迟的连线)
//----------------------------------------------------------------------------
module BUFG (
    output O,
    input  I
);
    assign #0.1 O = I;
endmodule

//----------------------------------------------------------------------------
// MMCME2_BASE : 锁相环/时钟管理单元的行为级简化模型
//   输出频率 = CLKIN × CLKFBOUT_MULT_F / (DIVCLK_DIVIDE × CLKOUTx_DIVIDE)
//   CLKOUT1 相对 CLKOUT0 的相移由 CLKOUT1_PHASE 决定(单位: 度)
//   LOCKED 在上电一段时间后拉高
//----------------------------------------------------------------------------
module MMCME2_BASE #(
    parameter BANDWIDTH          = "OPTIMIZED",
    parameter CLKFBOUT_MULT_F    = 8.0,
    parameter CLKFBOUT_PHASE     = 0.0,
    parameter CLKIN1_PERIOD      = 8.0,
    parameter DIVCLK_DIVIDE      = 1,
    parameter CLKOUT0_DIVIDE_F   = 8.0,
    parameter CLKOUT0_PHASE      = 0.0,
    parameter CLKOUT0_DUTY_CYCLE = 0.5,
    parameter CLKOUT1_DIVIDE     = 8,
    parameter CLKOUT1_PHASE      = 0.0,
    parameter CLKOUT1_DUTY_CYCLE = 0.5,
    parameter STARTUP_WAIT       = "FALSE"
)(
    input  CLKIN1,
    input  CLKFBIN,
    input  RST,
    input  PWRDWN,
    output CLKFBOUT,
    output CLKOUT0,
    output CLKOUT1,
    output LOCKED
);

    // VCO 周期 = 输入周期 × DIVCLK_DIVIDE / CLKFBOUT_MULT_F
    // 必须用 localparam(常量), 不能用 real 变量:
    // 否则后续表达式引用它会被判为"非常量表达式"(iverilog 报错)
    localparam real vco_per  = CLKIN1_PERIOD * DIVCLK_DIVIDE / CLKFBOUT_MULT_F;
    localparam real out0_per = vco_per * CLKOUT0_DIVIDE_F;
    localparam real out1_per = vco_per * CLKOUT1_DIVIDE;
    // 相移换算成时间: 周期 × 相位/360   (125MHz下 90° = 2ns)
    localparam real out1_dly = out1_per * CLKOUT1_PHASE / 360.0;

    reg locked_r = 1'b0;

    // 反馈输出: 与输入同频(简化)
    assign CLKFBOUT = CLKFBIN;

    // 模拟 PLL 锁定时间
    initial begin
        #120;
        locked_r = 1'b1;
    end

    //------------------------------------------------------------------
    // 关键: CLKOUT0 必须与输入时钟"相位锁定", 不能自由振荡。
    //   本工程 VCO 倍频后再分频, CLKOUT0 频率 = 输入频率(125M -> 125M),
    //   因此可以直接用"输入时钟的延迟副本"精确建模相位关系。
    //   CLKOUT1(200MHz, IDELAYCTRL 参考)频率 != 输入频率,
    //   用分频建模: 对 IDELAYCTRL 而言参考钟只要求频率正确、稳定翻转,
    //   相位无要求, 故用本地振荡器按 out1_per 建模即可。
    //------------------------------------------------------------------
    wire clk0_d, clk1_d;
    assign #0.2            clk0_d = CLKIN1;              // 0°  (0.2ns 模拟BUFG/布线延迟)
    assign #(0.2 + out1_dly) clk1_d = CLKIN1;            // 同频时的延迟副本(兼容旧用法)

    // 本地振荡器: 周期 = out1_per (本工程 5ns = 200MHz)
    reg clk1_osc = 1'b0;
    initial begin
        forever #(out1_per/2.0) clk1_osc = ~clk1_osc;
    end

    // 输出频率与输入相同 -> 相位锁定副本; 否则 -> 本地振荡(仅保证频率)
    wire same_freq = (out1_per == CLKIN1_PERIOD * DIVCLK_DIVIDE);
    assign CLKOUT0 = locked_r ? clk0_d : 1'b0;
    assign CLKOUT1 = locked_r ? (same_freq ? clk1_d : clk1_osc) : 1'b0;
    assign LOCKED  = locked_r;

endmodule

//----------------------------------------------------------------------------
// IDELAYE2 : 输入可调延迟线
//   真实器件: 0~31 tap, 每 tap = 1/(32*REFCLK) = 78.125ps@200MHz, 最大 2.5ns。
//   行为级  : 模拟延迟是亚纳秒级模拟量, 功能仿真无法(也不需要)表达 ——
//             tap 值本就是"上板实测校准"的对象, 仿真只验证
//             加载/扫描 FSM 的逻辑。这里仅建模 tap 寄存器, DATAOUT 直通
//             IDATAIN(等价 tap=0), 与 tb(SCAN_EN=0, tap=0) 的预期一致。
//----------------------------------------------------------------------------
module IDELAYE2 #(
    parameter CINVCTRL_SEL          = "FALSE",
    parameter DELAY_SRC             = "IDATAIN",
    parameter HIGH_PERFORMANCE_MODE = "FALSE",
    parameter IDELAY_TYPE           = "FIXED",
    parameter IDELAY_VALUE          = 0,
    parameter PIPE_SEL              = "FALSE",
    parameter REFCLK_FREQUENCY      = 200.0,
    parameter SIGNAL_PATTERN        = "DATA",
    parameter IDELAY_GROUP          = ""
)(
    input         C,
    input         REGRST,
    input         LD,
    input         CE,
    input         INC,
    input         CINVCTRL,
    input         LDPIPEEN,
    input  [4:0]  CNTVALUEIN,
    input         IDATAIN,
    input         DATAIN,
    output        DATAOUT
);
    reg [4:0] tap_r = IDELAY_VALUE[4:0];
    // VAR_LOAD: LD=1 时在 C 上升沿装载 CNTVALUEIN
    always @(posedge C) if (LD) tap_r <= CNTVALUEIN;
    assign DATAOUT = IDATAIN;   // 行为级直通(tap=0 等价)
endmodule

//----------------------------------------------------------------------------
// IDELAYCTRL : IDELAYE2 的参考时钟与校准控制
//   真实器件: REFCLK 必须为 200MHz, 上电校准后 RDY 拉高。
//   行为级  : REFCLK 仅作形式参数(行为级不校准), 复位释放后延时给出 RDY。
//----------------------------------------------------------------------------
module IDELAYCTRL (
    input  REFCLK,
    input  RST,
    output RDY
);
    reg rdy_r = 1'b0;
    initial #2000 rdy_r = 1'b1;             // 上电 2us 后视为校准完成
    always @(posedge RST) rdy_r <= 1'b0;
    always @(negedge RST) rdy_r <= #1000 1'b1;
    assign RDY = rdy_r;
endmodule

//============================================================================
// glbl : 行为级全局复位源(仅供 iverilog 等通用仿真器)
//
// 真实 Vivado 仿真由 $XILINX_VIVADO/data/verilog/src/unisims/glbl.v 提供,
// 其文件首行含有 `define GLBL, 因此下面这段会被 `ifndef GLBL 跳过, 不会重复。
// 而在 iverilog 下没有该定义, 这里提供一个等价实现, 使 IDDR/ODDR 的
// GSR 冻结行为在行为级模型中也能复现(与真实原语一致)。
//============================================================================
`ifndef GLBL
`timescale 1ps / 1ps
module glbl ();
    parameter ROC_WIDTH = 100000;   // 上电后 GSR 保持 1 的时长(ps) = 100ns
                                    // 注: 本模块单独用 1ps 时标, 与真实 glbl.v 一致

    reg GSR  = 1'b1;

    initial begin
        GSR  = 1'b1;
        #(ROC_WIDTH)
        GSR  = 1'b0;
    end
endmodule
`endif
