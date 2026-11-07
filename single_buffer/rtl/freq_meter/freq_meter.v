`timescale  1ns / 1ps
//==============================================================================
// 文件名称 : freq_meter.v
// 文件功能 : 板级实时测量 ①cam1_pclk 频率 ②摄像头帧率 ③HDMI 帧率
// 设计者：胡宽
// 创建日期 : 2026-09-26
//
// 设计要点 :
//   1. 纯观测模块 —— 只"读"信号，不接入任何数据通路，不影响原有功能。
//   2. 被测时钟速率允许【高于】参考时钟（84MHz 被测 / 50MHz 参考）。
//      做法：被测时钟先由它自己的域内一个极小分频器降速（默认 ÷64 → 1.31MHz），
//      然后在参考时钟域数它的边沿次数 × 2^DIV_LOG2 得到频率。
//      ⚠ 不要退回"被测域内用 32 位计数器直接数"的老写法：
//        本设计 cam1_pclk 域 hold 余量只有 0.143ns，老写法把它打崩了
//        （114 个 hold 违例 / THS -39.104ns）。
//   3. 资源极省：约几十个 LUT/FF，不包括任何 IP 核。被测域只 6 个 FF。
//
// 包含 3 个 module（单文件，方便一次性加进工程）:
//   ① freq_meter        —— 通用异步频率计（测 cam1_pclk）
//   ② pulse_rate_meter  —— 通用脉冲频率/周期计（测 vsync → 帧率）
//   ③ diag_freq_meter   —— 顶层封装：一次例化，三路结果全部输出
//==============================================================================


//==============================================================================
// ① 通用异步频率计
//==============================================================================
// 原理（低负载版）:
//   被测时钟域：一个 DIV_LOG2 位计数器，输出 2^(DIV_LOG2+1) 分频方波 div_out
//       ↓ 只需把 1 位 div_out 同步进参考时钟域（不再搬 32 位总线）
//   参考时钟域：在 GATE_MS 窗口内数 div_out 的边沿个数（上下沿都数，精度翻倍）
//       ↓ 窗口结束
//   freq_hz = 边沿数 × (1000/GATE_MS) × 2^DIV_LOG2
//
//   例：DIV_LOG2=5、GATE_MS=1000，实测 84MHz 时边沿数 = 2,625,000 → ×32 = 84,000,000 ✓
// ==============================================================================
module freq_meter #(
    parameter            REF_CLK_HZ = 50_000_000              ,   // 参考时钟频率(Hz)，本工程用 clk_50m = 50MHz
    parameter            GATE_MS    = 1000                    ,   // 门控时间(ms)：1000/500/250/200/100/50/25/20/10（须能整除 1000）
    parameter            CNT_WIDTH  = 32                      ,
    // [低负载版] 被测时钟先做 2^(DIV_LOG2+1) 分频，再在参考时钟域测量。
    //   为什么要分频：本设计 cam1_pclk 域原 hold 余量只有 0.143ns（见 xdc 注释），
    //   第一版直接在被测域放「32 位计数器 + 32 位跨域锁存 + 3 级同步器」，
    //   把该域 hold 打崩了（114 个 hold 违例 / THS -39ns）。
    //   现在被测域只剩「DIV_LOG2 位计数器 + 1 位寄存器」，负载降低一个数量级。
    //   取 5 → 84MHz 分频成 1.31MHz，用 50MHz 采样绰绰有余。
    parameter            DIV_LOG2   = 5
)(
    input  wire                     ref_clk                   ,   // 参考时钟
    input  wire                     ref_rst_n                 ,   // 参考时钟域复位，低电平有效
    input  wire                     meas_clk                  ,   // 【被测时钟】可异步，频率可高于参考时钟

    output reg  [CNT_WIDTH-1:0]     freq_hz                   ,   // 测得频率(Hz)
    output reg                      freq_valid                ,   // 结果更新脉冲（1 个 ref_clk 周期高）
    output reg                      meas_lost                     // 1 = 被测时钟无跳变（摄像头没输出时钟/未上电）
);

    localparam [CNT_WIDTH-1:0]  GATE_TICKS = (REF_CLK_HZ / 1000) * GATE_MS ;   // 测量窗口对应的参考时钟拍数
    // 换算到 Hz 的倍数：窗口 1ms 内的“分频后边沿数” × MULT = 频率(Hz)
    //   被测时钟 = 边沿数/秒 × 2^DIV_LOG2  →  MULT = (1000/GATE_MS) × 2^DIV_LOG2
    localparam [CNT_WIDTH-1:0]  MULT       = (1000 / GATE_MS) * (1 << DIV_LOG2) ;

    //------------------------------------------------------------------
    // 参考时钟域：测量窗口计数器（0 ~ GATE_TICKS-1 循环）
    //   窗口结束的处理在下面【参考时钟域：数边沿】那一段里，
    //   与边沿计数写在同一 always 块，省掉一个比较器。
    //------------------------------------------------------------------
    reg  [CNT_WIDTH-1:0]         gate_cnt                     ;

    //------------------------------------------------------------------
    // 被测时钟域：【极简分频器】—— 只有 DIV_LOG2 位计数器 + 1 位寄存器
    //   说明：本时钟域没有本地复位（异步复位会带来跨时钟释放问题），
    //         依靠 initial 初始化。Xilinx FPGA 支持 initial 初始化寄存器。
    //   div_out 的每个边沿被参考域采到，于是：
    //        meas_clk 频率 = 每秒边沿数 × 2^DIV_LOG2
    //------------------------------------------------------------------
    reg  [DIV_LOG2-1:0]         div_cnt       = {(DIV_LOG2){1'b0}};
    reg                         div_out       = 1'b0          ;

    always @(posedge meas_clk) begin
        if (div_cnt == {(DIV_LOG2){1'b1}}) begin
            div_cnt <= {(DIV_LOG2){1'b0}};
            div_out <= ~div_out;                          // 2^(DIV_LOG2+1) 分频输出
        end
        else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    //------------------------------------------------------------------
    // 参考时钟域：同步分频输出 → 数边沿 → 窗口结束换算频率
    //   div_out 最低也有 1MHz 量级，用 ref_clk 采样其边沿完全可靠，
    //   而且只需同步 1 位（原来要搬 32 位跨域总线）。
    //------------------------------------------------------------------
    reg                  [2:0]  div_sync                      ;
    reg                         div_d                         ;

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            div_sync <= 3'b000;
            div_d    <= 1'b0 ;
        end
        else begin
            div_sync <= {div_sync[1:0], div_out};
            div_d    <=  div_sync[2]                       ;
        end
    end

    wire                        div_edge = div_sync[2] ^ div_d;   // 上/下沿都算，精度翻倍

    reg  [CNT_WIDTH-1:0]        edge_cnt                      ;
    reg  [CNT_WIDTH-1:0]        edge_shadow                   ;
    reg                         win_end                       ;

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            gate_cnt    <= {(CNT_WIDTH){1'b0}};
            edge_cnt    <= {(CNT_WIDTH){1'b0}};
            edge_shadow <= {(CNT_WIDTH){1'b0}};
            win_end     <= 1'b0;
        end
        else if (gate_cnt == GATE_TICKS - 1'b1) begin   // 测量窗口结束
            gate_cnt    <= {(CNT_WIDTH){1'b0}};
            edge_shadow <= edge_cnt;                    // 先把计数值搬到快照，再清零
            edge_cnt    <= {(CNT_WIDTH){1'b0}};
            win_end     <= 1'b1;                        // 下一拍输出结果
        end
        else begin
            gate_cnt <= gate_cnt + 1'b1;
            win_end  <= 1'b0;
            if (div_edge)
                edge_cnt <= edge_cnt + 1'b1;
        end
    end

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            freq_hz    <= {(CNT_WIDTH){1'b0}};
            freq_valid <= 1'b0;
            meas_lost  <= 1'b1;
        end
        else begin
            freq_valid <= win_end;
            if (win_end) begin
                freq_hz   <= edge_shadow * MULT;                     // 换算成 Hz
                meas_lost <= (edge_shadow == {(CNT_WIDTH){1'b0}});   // 一个边沿都没有 → 没有时钟
            end
        end
    end

endmodule


//==============================================================================
// ② 通用脉冲频率 / 周期计（测量 vsync 这类低频脉冲）
//==============================================================================
// 原理:
//   脉冲先两级同步进参考时钟域（低频信号，直接采样安全）
//   · rate_hz    = 一个统计窗口内的【有效】脉冲个数 → 就是帧率 fps（整数）
//   · period_ns  = 相邻两个【有效】上升沿间隔(ns)   → 帧周期，可反推小数帧率
//   · glitch_cnt = 窗口内被当作毛刺滤掉的脉冲数      → 量化信号质量
//
// 毛刺过滤（2026-09-26 升级为"宽度 + 间隔"双判据）：
//   判据①【宽度】高电平持续 ≥ MIN_WIDTH_NS 才算真脉冲（默认 10us）
//        · 真实 vsync 脉冲：几十 us 起（OV5640 通常 4~10 行 ≈ 90~225us）
//        · 振铃/串扰干扰：  只有几 ns ~ 几十 ns
//        → 宽度差几百倍，这是最干净的判据
//   判据②【间隔】与上一个有效帧间隔 ≥ MIN_PERIOD_NS（默认 2ms）作为第二道保险
//        · 摄像头 30fps → 帧周期 33.3ms ≫ 2ms → 绝不会误杀
//        · HDMI   60fps → 帧周期 16.7ms ≫ 2ms → 绝不会误杀
//
//   两个判据【同时】满足才计为 1 帧，其余上升沿一律计入 glitch_cnt。
//   MIN_WIDTH_NS = 0 且 MIN_PERIOD_NS = 0 → 完全关闭过滤。
//
//   额外输出 high_ns = 最近一次高电平持续时长(ns)，用来判断"脉冲到底是宽还是窄"。
//
//   注：只看上升沿，与 vsync 的高低有效极性无关。
//==============================================================================
module pulse_rate_meter #(
    parameter REF_CLK_HZ    = 50_000_000               ,   // 参考时钟频率(Hz)
    parameter WINDOW_MS     = 1000                     ,   // 统计窗口(ms)，1000 → 每秒更新一次
    parameter TIMEOUT_MS    = 2000                     ,   // 超过此时间没脉冲 → 判定无信号
    parameter MIN_PERIOD_NS = 2_000_000                ,   // 间隔判据(ns)，0 = 不判间隔
    parameter MIN_WIDTH_NS  = 10_000                       // 宽度判据(ns)，0 = 不判宽度
)(
    input  wire             ref_clk                   ,
    input  wire             ref_rst_n                 ,
    input  wire             pulse_in                  ,   // 待测脉冲（如 vsync，可异步）

    output reg      [15:0]  rate_hz                   ,   // 窗口内【有效】脉冲数 = 帧率(fps)
    output reg      [31:0]  period_ns                 ,   // 相邻有效帧间隔(ns) = 帧周期
    output reg      [31:0]  high_ns                   ,   // 最近一次高电平持续时长(ns)【诊断用】
    output reg      [15:0]  glitch_cnt                ,   // 窗口内被滤掉的毛刺数（0 = 信号干净）
    output reg              rate_valid                ,   // 结果更新脉冲
    output reg              pulse_lost                    // 1 = 超时没脉冲（信号丢失）
);

    localparam [31:0] WIN_TICKS     = WINDOW_MS  * (REF_CLK_HZ / 1000);
    localparam [31:0] TIMEOUT_TICKS = TIMEOUT_MS * (REF_CLK_HZ / 1000);
    localparam [31:0] NS_PER_TICK   = 1_000_000_000 / REF_CLK_HZ;   // 50MHz → 20 ns/拍
    localparam [31:0] MIN_TICKS       = MIN_PERIOD_NS / NS_PER_TICK   ;   // 间隔阈值对应的 tick 数
    localparam [31:0] MIN_WIDTH_TICKS = MIN_WIDTH_NS  / NS_PER_TICK   ;   // 宽度阈值对应的 tick 数

    //------------------------------------------------------------------
    // 输入同步 + 上升沿检测
    //------------------------------------------------------------------
    reg      [2:0]  p_sync                            ;
    reg             p_d                               ;

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            p_sync <= 3'b000;
            p_d    <= 1'b0 ;
        end
        else begin
            p_sync <= {p_sync[1:0], pulse_in};
            p_d    <=  p_sync[2]                       ;
        end
    end

    wire            p_edge = p_sync[2] & ~p_d    ;

    //------------------------------------------------------------------
    // 高电平宽度测量：识别"真宽脉冲"，滤掉"窄毛刺"
    //   high_cnt   = 当前高电平已持续的 tick 数（低电平时清零）
    //   p_width_ok = 高电平持续够久时给出的【单次】确认脉冲（每段高电平只给一次）
    //------------------------------------------------------------------
    wire            sig_hi                              = p_sync[2]                          ;
    reg     [31:0]  high_cnt                          ;
    reg             ok_d                              ;   // 本段高电平是否已确认过

    wire            p_width_ok = sig_hi & ~ok_d & (high_cnt >= MIN_WIDTH_TICKS)   ;

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            high_cnt <= 32'd0;
            ok_d     <= 1'b0 ;
        end
        else begin
            high_cnt <= sig_hi ? (high_cnt + 1'b1) : 32'd0;
            if (!sig_hi)                              // 低电平：清除确认标志
                ok_d <= 1'b0;
            else if (p_width_ok)                      // 本段已确认，避免重复给脉冲
                ok_d <= 1'b1;
        end
    end

    //------------------------------------------------------------------
    // 帧周期：相邻两个【有效帧】之间的 tick 数
    //------------------------------------------------------------------
    reg     [31:0]  tick_cnt                          ;
    reg     [31:0]  period_ticks                      ;

    //------------------------------------------------------------------
    // 有效帧判定：宽度够 【且】 间隔够，两个条件同时满足才算 1 帧
    //------------------------------------------------------------------
    wire            p_frame  = p_width_ok & (tick_cnt >= MIN_TICKS)   ;   // 真帧脉冲

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            tick_cnt     <= 32'd0;
            period_ticks <= 32'd0;
        end
        else if (p_frame) begin
            period_ticks <= tick_cnt + 1'b1;     // 补上当前这一拍，否则会少 1 个参考时钟周期
            tick_cnt     <= 32'd0  ;
        end
        else if (tick_cnt != TIMEOUT_TICKS) begin  // 饱和在超时值：比较器从 32bit 进位链变成等值比较
            tick_cnt <= tick_cnt + 1'b1;
        end
    end

    //------------------------------------------------------------------
    // 最近一次【有效帧】的高电平持续时长（诊断"脉冲到底是宽还是窄"）
    //   只在下降沿那一拍锁存一次 ——
    //   否则低电平期间 high_cnt 已被清零，会反复把正确值覆盖成 0（上一版的 bug）
    //------------------------------------------------------------------
    reg     [31:0]  high_ticks    = 32'd0             ;
    reg             sig_hi_d      = 1'b0              ;
    reg             frame_hi      = 1'b0              ;   // 本段高电平是否已被确认为有效帧

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            high_ticks <= 32'd0;
            sig_hi_d   <= 1'b0 ;
            frame_hi   <= 1'b0 ;
        end
        else begin
            sig_hi_d <= sig_hi;
            if (!sig_hi)              frame_hi <= 1'b0;    // 低电平：本段结束
            else if (p_frame)         frame_hi <= 1'b1;    // 本段被确认为有效帧
            if (sig_hi_d && !sig_hi && frame_hi)           // 下降沿 且 本段是有效帧
                high_ticks <= high_cnt;
        end
    end

    //------------------------------------------------------------------
    // 统计窗口：窗口内数脉冲
    //------------------------------------------------------------------
    reg     [31:0]  win_cnt                           ;
    reg     [15:0]  pulse_cnt                         ;   // 有效帧计数
    reg     [15:0]  pulse_shadow                      ;   // 窗口结束时的有效帧快照
    reg     [15:0]  edge_c                            ;   // 所有上升沿计数（含毛刺）
    reg     [15:0]  glitch_shadow                     ;   // 窗口结束时的毛刺快照
    reg             win_end                           ;

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            win_cnt       <= 32'd0;
            pulse_cnt     <= 16'd0;
            pulse_shadow  <= 16'd0;
            edge_c        <= 16'd0;
            glitch_shadow <= 16'd0;
            win_end       <= 1'b0 ;
        end
        else if (win_cnt == WIN_TICKS - 1'b1) begin
            // 窗口最后一拍：先把累计值搬到 shadow，再清零；
            // win_end 下一拍才拉高，确保外部读到的是完整的窗口计数。
            win_cnt       <= 32'd0               ;
            pulse_shadow  <= pulse_cnt           ;
            glitch_shadow <= edge_c - pulse_cnt  ;   // 毛刺数 = 总上升沿数 − 有效帧数
            pulse_cnt     <= 16'd0               ;
            edge_c        <= 16'd0               ;
            win_end       <= 1'b1                ;
        end
        else begin
            win_cnt <= win_cnt + 1'b1;
            win_end <= 1'b0;
            if (p_frame)   pulse_cnt <= pulse_cnt + 1'b1;
            if (p_edge)    edge_c    <= edge_c    + 1'b1;
        end
    end

    //------------------------------------------------------------------
    // 窗口结束时锁存输出
    //------------------------------------------------------------------
    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            rate_hz    <= 16'd0;
            period_ns  <= 32'd0;
            high_ns    <= 32'd0;
            glitch_cnt <= 16'd0;
            rate_valid <= 1'b0 ;
            pulse_lost <= 1'b1 ;
        end
        else begin
            rate_valid <= win_end;
            if (win_end) begin
                rate_hz    <= pulse_shadow;                          // 有效帧数 → 直接是 fps
                glitch_cnt <= glitch_shadow;                         // 被滤掉的毛刺数
                period_ns  <= period_ticks * NS_PER_TICK;            // 帧周期(ns)
                high_ns    <= high_ticks   * NS_PER_TICK;            // 最近一次高电平宽度(ns)
                pulse_lost <= (tick_cnt == TIMEOUT_TICKS);           // 太久没脉冲（计数器已饱和）
            end
        end
    end

endmodule


//==============================================================================
// ③ 顶层封装：一次例化，同时给出 3 路结果
//==============================================================================
// 使用方法（只接 3 根被测线 + 参考时钟）：
//     .ref_clk    ← sys_clk        (50MHz)
//     .ref_rst_n  ← sys_rst_n
//     .cam_pclk   ← cam1_pclk
//     .cam_vsync  ← cam1_vsync
//     .hdmi_vsync ← hdmi_out_vsync
//
// 输出全部带 mark_debug，可用 Vivado ILA 直接观测。
//==============================================================================
module diag_freq_meter #(
    parameter REF_CLK_HZ = 50_000_000                 ,
    parameter GATE_MS    = 1000
)(
    input  wire             ref_clk                   ,   // ← sys_clk
    input  wire             ref_rst_n                 ,   // ← sys_rst_n
    input  wire             cam_pclk                  ,   // ← cam1_pclk
    input  wire             cam_vsync                 ,   // ← cam1_vsync
    input  wire             hdmi_vsync                ,   // ← hdmi_out_vsync

    (* mark_debug = "true" *) output wire [31:0] cam_pclk_freq_hz     ,   // cam1_pclk 实测频率(Hz)
    (* mark_debug = "true" *) output wire        cam_pclk_valid       ,   // 频率结果更新脉冲
    (* mark_debug = "true" *) output wire        cam_pclk_lost        ,   // 1=摄像头没输出时钟

    (* mark_debug = "true" *) output wire [15:0] cam_fps              ,   // 摄像头实测帧率(fps)【已滤毛刺】
    (* mark_debug = "true" *) output wire [15:0] cam_glitch_cnt       ,   // 摄像头 vsync 上被滤掉的毛刺数/秒
    (* mark_debug = "true" *) output wire [31:0] cam_vsync_high_ns    ,   // 摄像头 vsync 最近一次高电平宽度(ns)【诊断】
    (* mark_debug = "true" *) output wire [31:0] cam_frame_period_ns  ,   // 摄像头帧周期(ns)
    (* mark_debug = "true" *) output wire        cam_vsync_lost       ,   // 1=摄像头没输出 vsync

    (* mark_debug = "true" *) output wire [15:0] hdmi_fps             ,   // HDMI 实测帧率(fps)【已滤毛刺】
    (* mark_debug = "true" *) output wire [15:0] hdmi_glitch_cnt      ,   // HDMI vsync 上被滤掉的毛刺数/秒
    (* mark_debug = "true" *) output wire [31:0] hdmi_vsync_high_ns   ,   // HDMI vsync 最近一次高电平宽度(ns)【诊断】
    (* mark_debug = "true" *) output wire [31:0] hdmi_frame_period_ns ,   // HDMI 帧周期(ns)
    (* mark_debug = "true" *) output wire        hdmi_vsync_lost      ,   // 1=HDMI 没输出 vsync

    (* mark_debug = "true" *) output wire        rate_valid               // 帧率结果更新脉冲
);

    wire        cam_rate_valid                        ;
    wire        hdmi_rate_valid                       ;

    //---------- ① cam1_pclk 频率 ----------
    freq_meter #(
        .REF_CLK_HZ (REF_CLK_HZ                      ),
        .GATE_MS    (GATE_MS                         )
    ) u_freq_meter_cam_pclk (
        .ref_clk    (ref_clk                         ),
        .ref_rst_n  (ref_rst_n                       ),
        .meas_clk   (cam_pclk                        ),
        .freq_hz    (cam_pclk_freq_hz                ),
        .freq_valid (cam_pclk_valid                  ),
        .meas_lost  (cam_pclk_lost                   )
    );

    //---------- ② 摄像头帧率 ----------
    pulse_rate_meter #(
        .REF_CLK_HZ    (REF_CLK_HZ                   ),
        .WINDOW_MS     (1000                         ),
        .TIMEOUT_MS    (2000                         ),
        .MIN_PERIOD_NS (2000_000                     ),  // 2ms：帧周期 33.3ms，不会被误杀
        .MIN_WIDTH_NS  (10000                        )   // 10us：真 vsync 宽几十 us，窄毛刺全滤掉
    ) u_rate_meter_cam_vsync (
        .ref_clk    (ref_clk                         ),
        .ref_rst_n  (ref_rst_n                       ),
        .pulse_in   (cam_vsync                       ),
        .rate_hz    (cam_fps                         ),
        .period_ns  (cam_frame_period_ns             ),
        .high_ns    (cam_vsync_high_ns               ),
        .glitch_cnt (cam_glitch_cnt                  ),
        .rate_valid (cam_rate_valid                  ),
        .pulse_lost (cam_vsync_lost                  )
    );

    //---------- ③ HDMI 帧率 ----------
    pulse_rate_meter #(
        .REF_CLK_HZ    (REF_CLK_HZ                   ),
        .WINDOW_MS     (1000                         ),
        .TIMEOUT_MS    (2000                         ),
        .MIN_PERIOD_NS (2000_000                     ),  // 2ms：HDMI 帧周期 16.7ms，不会被误杀
        .MIN_WIDTH_NS  (10000                        )   // 10us：HDMI vsync 脉宽 ~100us 量级
    ) u_rate_meter_hdmi_vsync (
        .ref_clk    (ref_clk                         ),
        .ref_rst_n  (ref_rst_n                       ),
        .pulse_in   (hdmi_vsync                      ),
        .rate_hz    (hdmi_fps                        ),
        .period_ns  (hdmi_frame_period_ns            ),
        .high_ns    (hdmi_vsync_high_ns              ),
        .glitch_cnt (hdmi_glitch_cnt                 ),
        .rate_valid (hdmi_rate_valid                 ),
        .pulse_lost (hdmi_vsync_lost                 )
    );

    assign  rate_valid = cam_rate_valid | hdmi_rate_valid;

endmodule
