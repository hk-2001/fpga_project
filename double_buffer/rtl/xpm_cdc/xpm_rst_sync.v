`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 设计者：胡宽
// 目的：用 Xilinx 官方 XPM_CDC 原语解决「rst_n 跨时钟域异步释放」问题
//
// 背景（问题）：
//   顶层 rst_n = sys_rst_n & ddr3_init_done & !ui_clk_sync_rst & locked
//   这是一个【组合与门】，被直接送到 3 个不同时钟域：
//     · 84 MHz  (cam1_pclk)  → ov5640_data.camera_rst_n
//     · 74.17 MHz (clk_74_25m) → vga_ctrl.hdmi_rst_n
//     · 50 MHz  (clk_50m)    → ov5640_top / hdmi_drvier 的配置逻辑
//   各域均写成 always @(posedge xxx or negedge rst_n)，即【异步释放】。
//   风险：释放沿落在目标时钟的建立/保持窗口内 → recovery/removal 违例，
//        或同域内寄存器不同拍退出复位 → 状态机初值不一致。
//
// 解法：
//   用 xpm_cdc_async_rst（异步断言、同步释放）为每个时钟域各生成一份
//   同步释放的复位。这是 Xilinx 官方原语：
//     · 自动带 ASYNC_REG 属性，Vivado 布局时保证同步寄存器紧邻，降低亚稳态
//     · 无需手写两级 FF，也无需手写 set_false_path（原语自带时序约束）
//
//
// 原语端口（Vivado 2018.3 实测）：
//   xpm_cdc_async_rst #(
//       .DEST_SYNC_FF(4),        // 目标域同步级数，2~10，推荐 4
//       .INIT_SYNC_FF(0),        // 仿真时同步寄存器初值
//       .RST_ACTIVE_HIGH(0)      // 0 = 低有效复位（本项目 rst_n 为低有效）
//   ) (
//       .src_arst (rst_in),      // 源异步复位输入
//       .dest_clk (clk),         // 目标时钟
//       .dest_arst(rst_out)      // 目标域同步释放后的复位
//   );
//////////////////////////////////////////////////////////////////////////////////

module xpm_rst_sync (
    // ---------- 源复位（来自顶层组合与门，异步，低有效） ----------
    input  wire                         rst_n_src           ,   // = rst_n

    // ---------- 初始化完成（用于 cam 域：未初始化完则一直保持复位） ----------
    input  wire                         sys_init_done       ,   // = cam_cfg_done & ddr3_init_done

    // ---------- 三个目标时钟域 ----------
    input  wire                         cam_clk             ,   // 84 MHz    (cam1_pclk)
    input  wire                         vga_clk             ,   // 74.17 MHz (clk_74_25m)
    input  wire                         cfg_clk             ,   // 50 MHz    (clk_50m)

    // ---------- 各域同步释放后的复位（低有效） ----------
    output wire                         rst_n_cam           ,   // → ov5640_data.camera_rst_n
    output wire                         rst_n_vga           ,   // → vga_ctrl.hdmi_rst_n
    output wire                         rst_n_cfg               // → ov5640_top / hdmi_drvier 配置逻辑
);

//==========================================================================
// 1) 84 MHz 域（摄像头采集域）
//    复位条件 = rst_n 有效「或」系统未初始化完成
//    把 (rst_n & sys_init_done) 整体送入原语，由原语在 cam 域同步释放，
//    这样既保留"未初始化完一直复位"的原有语义，又消除异步释放风险。
//==========================================================================
wire    cam_rst_src;

assign  cam_rst_src = rst_n_src & sys_init_done;

xpm_cdc_async_rst #(
    .DEST_SYNC_FF                       (4                  ),   // 同步级数 4
    .INIT_SYNC_FF                       (0                  ),
    .RST_ACTIVE_HIGH                    (0                  )    // 低有效
) u_rst_sync_cam (
    .src_arst                           (cam_rst_src        ),
    .dest_clk                           (cam_clk            ),
    .dest_arst                          (rst_n_cam          )
);

//==========================================================================
// 2) 74.17 MHz 域（HDMI 显示域 → vga_ctrl）
//==========================================================================
xpm_cdc_async_rst #(
    .DEST_SYNC_FF                       (4                  ),
    .INIT_SYNC_FF                       (0                  ),
    .RST_ACTIVE_HIGH                    (0                  )
) u_rst_sync_vga (
    .src_arst                           (rst_n_src          ),
    .dest_clk                           (vga_clk            ),
    .dest_arst                          (rst_n_vga          )
);

//==========================================================================
// 3) 50 MHz 域（SCCB / DDC 配置域）
//==========================================================================
xpm_cdc_async_rst #(
    .DEST_SYNC_FF                       (4                  ),
    .INIT_SYNC_FF                       (0                  ),
    .RST_ACTIVE_HIGH                    (0                  )
) u_rst_sync_cfg (
    .src_arst                           (rst_n_src          ),
    .dest_clk                           (cfg_clk            ),
    .dest_arst                          (rst_n_cfg          )
);

endmodule
