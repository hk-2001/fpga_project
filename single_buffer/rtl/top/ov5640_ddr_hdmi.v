
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/21 16:33:22
// Design Name: HUKUAN
// Module Name: ov5640_ddr_hdmi
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module ov5640_ddr_hdmi #(
    // [FIX/SIM] 帧尺寸做成顶层参数，方便仿真时用小帧缩短仿真时间；
    // 综合上板时保持默认 1280x720 即与原始设计一致。
    parameter                           IMAGE_WIDTH                 = 1280                 ,
   parameter                           IMAGE_HEIGHT                = 720                  ,
    // [DIAG] 彩条测试开关：1=输出8色竖彩条(绕过摄像头/DDR，定位偏绿与分屏根因)，0=正常显示
    parameter                           COLOR_TEST                  = 1'b0
)
(
    input  wire                         sys_clk                    ,//系统时钟
    input  wire                         sys_rst_n                  ,//系统复位，低电平有效
//摄像头接口
    output wire                         cam_rst_n                  ,//摄像1与2头复位信号，低电平有效
    output wire                         cam_pwdn                   ,//摄像1与2头时钟选择信号
    // output  wire            xclk,      //摄像头上板载了24MHZ晶振，直接使用 不由FPGA产生了
    
    input  wire                         cam1_pclk                  ,//摄像1头数据像素时钟
    input  wire                         cam1_vsync                 ,//摄像1头场同步信号
    input  wire                         cam1_href                  ,//摄像1头行同步信号
    input  wire          [   7: 0]      cam1_data                  ,//摄像1头数据
    output wire                         sccb1_scl                  ,//摄像头1SCCB_SCL线
    inout  wire                         sccb1_sda                  ,//摄像头1SCCB_SDA线
//HDMI
    output wire                         ddc_scl                    ,//hdmi芯片配置scl
    inout  wire                         ddc_sda                    ,//hdmi芯片配置sda
    output wire                         hdmi_out_clk               ,//hdmi输出时钟
    output wire                         hdmi_out_rst_n             ,//hdmi复位
    (* mark_debug = "true" *) output wire hdmi_out_hsync         ,//hdmi输出行同步信号
    (* mark_debug = "true" *) output wire hdmi_out_vsync         ,//hdmi输出场同步信号
    output wire          [  23: 0]      hdmi_out_rgb               ,//hdmi输出像素信息
    (* mark_debug = "true" *) output wire hdmi_out_de            ,//hdmi有效


//DDR3接口
    inout                [  31: 0]      ddr3_dq                    ,//数据线
    inout                [   3: 0]      ddr3_dqs_n                 ,//数据选取脉冲差分信号
    inout                [   3: 0]      ddr3_dqs_p                 ,//数据选取脉冲差分信号
    output               [  14: 0]      ddr3_addr                  ,//地址线
    output               [   2: 0]      ddr3_ba                    ,//bank线
    output                              ddr3_ras_n                 ,//行使能信号，低电平有效
    output                              ddr3_cas_n                 ,//列使能信号，低电平有效
    output                              ddr3_we_n                  ,//写使能信号，低电平有效
    output                              ddr3_reset_n               ,//ddr3复位
    output               [   0: 0]      ddr3_ck_p                  ,//ddr3差分时钟
    output               [   0: 0]      ddr3_ck_n                  ,//ddr3差分时钟
    output               [   0: 0]      ddr3_cke                   ,//ddr3时钟使能信号
    output               [   0: 0]      ddr3_cs_n                  ,//ddr3片选信号
    output               [   3: 0]      ddr3_dm                    ,//ddr3掩码
    output               [   0: 0]      ddr3_odt                   //odt阻抗

);
//------------------pll时钟--------------------
    // wire                                clk_24m; 独立晶振 不由fpga提供 xclk
    wire                                clk_50m                    ;
    wire                                clk_200m                   ;
    wire                                clk_74_25m                 ;
    (* mark_debug = "true" *) wire      locked                     ;
    // wire                                locked2                     ;
//--------------------camera------------------
    assign                              cam_rst_n                   = 1                    ;
    assign                              cam_pwdn                    = 0                    ;//如果要控制这个信号 需要遵守复位时序 数据手册里面有，我这里不需要控制我就直接把它置为0了
    wire                                rst_n                      ;
    // [XPM-CDC] 由 xpm_rst_sync 产生的「各时钟域同步释放」复位（低有效）
    wire                                rst_n_cam                  ;// 84MHz    摄像头采集域(ov5640_data)
    wire                                rst_n_vga                  ;// 74.17MHz HDMI 显示域(vga_ctrl)
    wire                                rst_n_cfg                  ;// 50MHz    配置/I2C 域
    (* mark_debug = "true" *) wire      sys_init_done              ;
    (* mark_debug = "true" *) wire      cam_cfg_done               ;
    (* mark_debug = "true" *) wire      cam1_wr_en                 ;
    wire                 [  15: 0]      cam1_data_out              ;//输出到写fifo的数据
//------------------ddr3------------------------
    (* mark_debug = "true" *) wire      ddr3_init_done             ;
    (* mark_debug = "true" *) wire      camera_done                ;

   // ==================== 输出mig侧的时钟和复位 ====================
    wire                                ui_clk                     ;//100MHZ DDR分频得到 输出
    wire                                ui_clk_sync_rst            ;
//---------------------------hdmi-----------------------
    (* mark_debug = "true" *) reg       camera_done_toggle         ;//camera_done在100MHZ时钟域做了处理传过来的电平翻转信号
    reg                                 camera_done_d1             ;//用于边沿检测
    wire                 [  15: 0]      pix_data                   ;//读fifo数据输出
    (* mark_debug = "true" *) wire      hdmi_cfg_done              ;
    wire                 [  15: 0]      rgb                        ;//要做处理 填充为RGB888
    (* mark_debug = "true" *) wire      hdmi_rd_en                 ;//读fifo使能
    wire                 [  11: 0]      pix_y                      ;
    wire                 [  11: 0]      pix_x                      ;

//==================== [DIAG] 频率/帧率测量 ====================
    wire                 [  31: 0]      diag_cam_pclk_freq_hz      ;
    wire                                diag_cam_pclk_valid        ;
    wire                                diag_cam_pclk_lost         ;
    wire                 [  15: 0]      diag_cam_fps               ;
    wire                 [  15: 0]      diag_cam_glitch_cnt        ;   // vsync 毛刺数/秒（0 = 信号干净）
    wire                 [  31: 0]      diag_cam_vsync_high_ns     ;   // vsync 最近一次高电平宽度(ns)【诊断关键】
    wire                 [  31: 0]      diag_cam_frame_period_ns   ;
    wire                                diag_cam_vsync_lost        ;
    wire                 [  15: 0]      diag_hdmi_fps              ;
    wire                 [  15: 0]      diag_hdmi_glitch_cnt       ;   // HDMI vsync 毛刺数/秒
    wire                 [  31: 0]      diag_hdmi_vsync_high_ns    ;   // HDMI vsync 最近一次高电平宽度(ns)
    wire                 [  31: 0]      diag_hdmi_frame_period_ns  ;
    wire                                diag_hdmi_vsync_lost       ;
    wire                                diag_rate_valid            ;

//camera_done 做处理：检测上升沿，每来一次写完成翻转一次
always@(posedge ui_clk or posedge ui_clk_sync_rst)
begin
    if(ui_clk_sync_rst) begin
        camera_done_d1    <= 1'b0;
        camera_done_toggle <= 1'b0;
    end
    else begin
        camera_done_d1 <= camera_done;
        if(camera_done && !camera_done_d1)
            camera_done_toggle <= ~camera_done_toggle;
    end
end

// [DIAG] 8 色竖彩条（按 pix_x 分段），用于一次烧板定位偏绿/分屏根因：
//   8色全对   -> 显示通路(SiI9134配置+RGB888)正常，绿色来自摄像头数据
//   彩条错色  -> 显示端问题(HDMI芯片输入格式)
//   彩条错位  -> 分屏根因在显示端
wire [23:0] color_bar;
assign color_bar = (pix_x < 12'd160)  ? 24'hFFFFFF :   // 白
                   (pix_x < 12'd320)  ? 24'hFFFF00 :   // 黄
                   (pix_x < 12'd480)  ? 24'h00FFFF :   // 青
                   (pix_x < 12'd640)  ? 24'h00FF00 :   // 绿
                   (pix_x < 12'd800)  ? 24'hFF00FF :   // 品红
                   (pix_x < 12'd960)  ? 24'hFF0000 :   // 红
                   (pix_x < 12'd1120) ? 24'h0000FF :   // 蓝
                                        24'h000000;    // 黑

//填充RGB888 输出到HDMI编码芯片（RGB565 -> RGB888，低位补 0）
assign hdmi_out_rgb = (COLOR_TEST == 1'b1) ? color_bar
                                           : {{rgb[15:11], 3'b0},
                                              {rgb[10:5],  2'b0},
                                              {rgb[4:0],   3'b0}};

assign hdmi_out_clk = clk_74_25m;

assign hdmi_out_rst_n = sys_rst_n;

//sys_init_done
assign sys_init_done = (cam_cfg_done && ddr3_init_done);

//rst_n
assign rst_n = sys_rst_n & ddr3_init_done & (!ui_clk_sync_rst) & locked;

// [FIX] MIG sys_rst 低有效：PLL 锁定且外部复位释放后应输出高电平
assign ddr3_rst_n = sys_rst_n & locked;

 clk_wiz_0 instance_name
    (
     // Clock out ports
     .clk_out1(clk_74_25m),       // output clk_out1
     .clk_out2(clk_200m),      // output clk_out2
    .clk_out3(clk_50m),    // output clk_out3
    // Status and control signals
    .reset(!sys_rst_n),       // input reset
    .locked(locked),          // output locked
    // Clock in ports
     .clk_in1(sys_clk));       // input clk_in1

//==================== [XPM-CDC] 复位同步 ====================
// 问题：rst_n = sys_rst_n & ddr3_init_done & !ui_clk_sync_rst & locked 是一个【组合与门】，
//       含 ui_clk(100M) 域的 ui_clk_sync_rst、MIG 的 ddr3_init_done、clk_wiz 的 locked，
//       原本被直接送到 84M / 74.17M / 50M 三个时钟域，各域寄存器均写成
//       always @(posedge xxx or negedge rst_n) —— 即【异步释放】。
//       风险：释放沿落在目标时钟建立/保持窗口内 → recovery/removal 违例；
//             或同域内寄存器不同拍退出复位 → 状态机初值不一致。
//
// 解法：用 Xilinx 官方 XPM_CDC 原语 xpm_cdc_async_rst（异步断言、同步释放），
//       为每个时钟域各生成一份同步释放的复位。
//       原语自带 ASYNC_REG 属性与时序约束，【无需】在 XDC 中额外添加约束。
//
// 注意：两个异步 FIFO(wr/rd_ddr3_fifo) 的复位【保持原样、不经过本模块】——
//       FIFO Generator IP 内部已用 xpm_cdc_sync_rst 完成复位同步，
//       并提供 wr_rst_busy / rd_rst_busy 握手（下游 fifo_to_axi4 已依赖），
//       外部再串同步器会破坏该握手（v1 黑屏即此症状）。
xpm_rst_sync u_xpm_rst_sync (
    .rst_n_src                          (rst_n                     ),// 源复位（低有效、异步）
    .sys_init_done                      (sys_init_done             ),// 初始化完成（cam 域复位会等它）
    .cam_clk                            (cam1_pclk                 ),// 84MHz    采集域
    .vga_clk                            (clk_74_25m                ),// 74.17MHz 显示域
    .cfg_clk                            (clk_50m                   ),// 50MHz    配置域
    .rst_n_cam                          (rst_n_cam                 ),
    .rst_n_vga                          (rst_n_vga                 ),
    .rst_n_cfg                          (rst_n_cfg                 )
);

// clk_wiz_1 clk_wiz_1
//    (
//     // Clock out ports
//     .clk_out1(clk_74_25m),     // output clk_out1
//     // Status and control signals
//     .reset(~sys_rst_n), // input reset
//     .locked(locked2),       // output locked
//    // Clock in ports
//     .clk_in1(clk_50m));      // input clk_in1
// clk_wiz_0 instance_name
//    (
//     // Clock out ports
//     .clk_out1(clk_50m),       // output clk_out1
//     .clk_out2(clk_200m),     // output clk_out2
//     // Status and control signals
//     .reset(~sys_rst_n),       // input reset
//     .locked(locked1),       // output locked
//    // Clock in ports
//     .clk_in1(sys_clk));      // input clk_in1
ov5640_top ov5640_top_inst(
    .sys_clk                            (clk_50m                   ),
    .sys_rst_n                          (rst_n_cfg                 ),// [XPM-CDC] 原 rst_n → 50MHz 域同步释放复位
    .camera_rst_n                       (rst_n_cam                 ),// [XPM-CDC] 新增：84MHz 域同步释放复位
    .sys_init_done                      (sys_init_done             ),
    .ov5640_pclk                        (cam1_pclk                 ),
    .ov5640_href                        (cam1_href                 ),
    .ov5640_vsync                       (cam1_vsync                ),
    .ov5640_data                        (cam1_data                 ),
    .cfg_done                           (cam_cfg_done              ),
    .sccb_scl                           (sccb1_scl                 ),
    .sccb_sda                           (sccb1_sda                 ),
    .ov5640_wr_en                       (cam1_wr_en                ),
    .ov5640_data_out                    (cam1_data_out             )
);

hdmi_drvier hdmi_drvier_inst(
    .sys_clk                            (clk_50m                   ),
    .hdmi_rst_n                         (rst_n_vga                 ),// [XPM-CDC] 原 rst_n → 74.17MHz 域同步释放复位
    .sys_rst_n                          (rst_n_cfg                 ),// [XPM-CDC] 原 sys_rst_n → 50MHz 域同步释放复位
    .vga_clk                            (clk_74_25m                ),
    .camera_done_toggle                 (camera_done_toggle        ),
    .pix_data                           (pix_data                  ),
    .ddc_scl                            (ddc_scl                   ),
    .ddc_sda                            (ddc_sda                   ),
    .cfg_done                           (hdmi_cfg_done             ),
    .rgb_valid                          (hdmi_out_de               ),
    .rgb                                (rgb                       ),
    .pix_data_req                       (hdmi_rd_en                ),
    .hsync                              (hdmi_out_hsync            ),
    .vsync                              (hdmi_out_vsync            ),
    .pix_y                              (pix_y                     ),
    .pix_x                              (pix_x                     )
);

//==================== [FIX] FIFO 复位：消除"按复位键后图像错位" ====================
// 现象：上电时图像正常，一按复位键图像就打散 / 拼接错乱。
// 原因：原来 .wrfifo_rst(1'b0) / .rdfifo_rst(1'b0) —— 两个 FIFO 从不复位。
//       · 上电时 FIFO 是确定初值（干净）→ 图像正常；
//       · 按复位键时【摄像头本身并没有复位】（cam_rst_n 硬接 1，它一直在输出），
//         FPGA 复位释放后接着往【装着上一帧残余像素】的 FIFO 里写，
//         读出的数据流 = "旧帧尾巴 + 新帧" → 起点偏移 → 图像打散。
// 修法：与系统复位同步，把两个 FIFO 一起复位（高有效，保持足够长时间）。
//       摄像头要等 I2C 配置完（几十 ms）才有数据，复位远早于数据，不丢有效像素。
// ---------------------------------------------------------------------------
// 【v2 说明】v1 用 cam1_pclk / clk_74_25m 各自计数产生复位，实测导致【按复位黑屏】：
//   若复位期间摄像头 PCLK 暂时消失，计数器不推进 → wrfifo_rst 一直保持
//   → 写 FIFO 永久复位 → wr_rst_busy 常高 → fifo_to_axi4 一直等待
//   → 不写 DDR → camera_w_done 不来 → 读侧 rd_enable 永不启动 → 黑屏。
//
// v2 改法：用【常驻的 sys_clk】产生复位，不依赖任何派生时钟域，
//   保证复位一定会释放；并且在"系统未初始化完成"期间一直保持复位，
//   初始化完成后再保持 1024 拍（20.5us @50MHz）确保清干净，然后释放。
//   释放时刻远早于数据流开始（摄像头 I2C 配置要几十 ms），不丢有效像素。
// ---------------------------------------------------------------------------
reg  [9:0]  fifo_rst_cnt          ;
reg         fifo_rst_sys          ;
reg         sys_init_done_d1      ;   // sys_init_done 同步到 sys_clk 域
reg         sys_init_done_s       ;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        sys_init_done_d1 <= 1'b0 ;
        sys_init_done_s  <= 1'b0 ;
    end
    else begin
        sys_init_done_d1 <= sys_init_done ;   // 跨域，打两拍
        sys_init_done_s  <= sys_init_done_d1;
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        fifo_rst_cnt <= 10'd0 ;
        fifo_rst_sys <= 1'b1  ;          // 复位期间保持复位
    end
    else if (!sys_init_done_s) begin
        fifo_rst_cnt <= 10'd0 ;
        fifo_rst_sys <= 1'b1  ;          // 还没配置好 → 一直清
    end
    else if (fifo_rst_cnt != 10'd1023) begin
        fifo_rst_cnt <= fifo_rst_cnt + 1'b1;
        fifo_rst_sys <= 1'b1  ;          // 配置好后再保持 1024 拍
    end
    else begin
        fifo_rst_sys <= 1'b0  ;          // 释放
    end
end

assign  wrfifo_rst_s = fifo_rst_sys ;
assign  rdfifo_rst_s = fifo_rst_sys ;

// ===========================================================================
// 【v1 备份 —— 当前未使能，整段以注释形式保留，便于随时切回对比】
//
// v1 上板实测表现：
//   ✅ 拼接错乱【彻底消失】
//      → 这一条很关键：证明根因确实是 FIFO 残留，不是"读追写"的撕裂，
//        因此【不需要乒乓双缓冲】。
//   ⚠ 但偶尔黑屏 / 卡住：
//      用 cam1_pclk 计数，复位期间 PCLK 一旦消失，计数器就不推进
//      → wrfifo_rst 常高 → 写 FIFO 永久复位 → 数据流断 → 黑屏。
//
// 想切回 v1 时：
//   1) 把上面 v2 的 reg 声明 + 两个 always + 两行 assign 整段注释掉
//   2) 把下面这段每行开头的 "//" 去掉
//   注意：v1 里 wrfifo_rst_s / rdfifo_rst_s 是【reg】，v2 里是 assign 出来的；
//        切换时两处不能同时存在，否则多驱动报错。
//
// reg  [5:0]  wrfifo_rst_cnt ;
// reg         wrfifo_rst_s   ;
// reg  [5:0]  rdfifo_rst_cnt ;
// reg         rdfifo_rst_s   ;
//
// // 写 FIFO 复位：在 wr_clk(cam1_pclk) 域，保持 32 个周期
// always @(posedge cam1_pclk or negedge sys_rst_n) begin
//     if (!sys_rst_n) begin
//         wrfifo_rst_cnt <= 6'd0 ;
//         wrfifo_rst_s   <= 1'b1 ;          // 复位期间保持复位
//     end
//     else if (wrfifo_rst_cnt != 6'd31) begin
//         wrfifo_rst_cnt <= wrfifo_rst_cnt + 1'b1;
//         wrfifo_rst_s   <= 1'b1 ;
//     end
//     else begin
//         wrfifo_rst_s   <= 1'b0 ;
//     end
// end
//
// // 读 FIFO 复位：在 rd_clk(clk_74_25m) 域，保持 32 个周期
// always @(posedge clk_74_25m or negedge sys_rst_n) begin
//     if (!sys_rst_n) begin
//         rdfifo_rst_cnt <= 6'd0 ;
//         rdfifo_rst_s   <= 1'b1 ;
//     end
//     else if (rdfifo_rst_cnt != 6'd31) begin
//         rdfifo_rst_cnt <= rdfifo_rst_cnt + 1'b1;
//         rdfifo_rst_s   <= 1'b1 ;
//     end
//     else begin
//         rdfifo_rst_s   <= 1'b0 ;
//     end
// end
// ===========================================================================

ddr3_ctrl_2port #(
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              )
) ddr3_ctrl_2port_inst(
    .ddr3_clk200m                       (clk_200m                  ),
    // [FIX] MIG 的 sys_rst 在 mig_a.prj 中配置为 ACTIVE LOW，
    // 原代码 (~sys_rst_n)|(~locked) 是低有效时的反相，导致 MIG 永久复位。
    .ddr3_rst                           (ddr3_rst_n                ),
    .ddr3_init_done                     (ddr3_init_done            ),//当DDR3初始化完成，并且mmcm locked也完成初始化时，才置1

    .wr_clk                             (cam1_pclk                 ),
    .din                                (cam1_data_out             ),
    .wr_en                              (cam1_wr_en                ),
    .wrfifo_rst                         (wrfifo_rst_s              ),// [FIX] 复位时清空写FIFO，消除残留像素
    .full                               (                          ),
    .wr_data_count                      (                          ),

    .rd_clk                             (clk_74_25m                ),
    .rdfifo_rst                         (rdfifo_rst_s              ),// [FIX] 复位时清空读FIFO
    .rd_en                              (hdmi_rd_en                ),
    .dout                               (pix_data                  ),
    .empty                              (                          ),
    .rd_data_count                      (                          ),
    // DDR3接口
    .ddr3_addr                          (ddr3_addr                 ),
    .ddr3_ba                            (ddr3_ba                   ),
    .ddr3_cas_n                         (ddr3_cas_n                ),
    .ddr3_ck_n                          (ddr3_ck_n                 ),
    .ddr3_ck_p                          (ddr3_ck_p                 ),
    .ddr3_cke                           (ddr3_cke                  ),
    .ddr3_ras_n                         (ddr3_ras_n                ),
    .ddr3_reset_n                       (ddr3_reset_n              ),
    .ddr3_we_n                          (ddr3_we_n                 ),
    .ddr3_dq                            (ddr3_dq                   ),
    .ddr3_dqs_n                         (ddr3_dqs_n                ),
    .ddr3_dqs_p                         (ddr3_dqs_p                ),
    .ddr3_cs_n                          (ddr3_cs_n                 ),
    .ddr3_dm                            (ddr3_dm                   ),
    .ddr3_odt                           (ddr3_odt                  ),

    // ==================== 输出mig侧的时钟和复位 ====================
    .ui_clk                             (ui_clk                    ),//100MHZ DDR分频得到 输出
    .ui_clk_sync_rst                    (ui_clk_sync_rst           ),
    //==================== 实验接口 ====================
    .w_done                             (camera_done               )
);

//==================== [DIAG] 频率/帧率测量模块 ====================
// 目的：实测 cam1_pclk 频率、摄像头帧率、HDMI 帧率
// 说明：纯观测模块，只"读"信号，不接入数据通路，剪掉也不影响显示
//       观测：输出端口已 mark_debug → 综合后 Tools → Set Up Debug 挂 ILA
//
// [重要] 参考时钟用 clk_50m（clk_wiz 的 clk_out3），不要用 sys_clk：
//    sys_clk 在本顶层里只接进了 clk_wiz 的 clk_in1，从未作为普通逻辑时钟使用，
//    综合后这些寄存器没有可识别的时钟域 → Set Up Debug 里显示 "undefined"，
//    导致 ILA 无法指定采样时钟（Finish 灰掉）。
//    clk_50m 与 sys_clk 同频（50MHz，clk_wiz 1:1 输出），测量精度完全一致，
//    而且它已经被工程里现有的 u_ila_1 当作采样时钟用（instance_name/inst/clk_out3），
//    证明该时钟域工具完全认得。
diag_freq_meter #(
    .REF_CLK_HZ                         (50_000_000                )
) u_diag_freq_meter (
    .ref_clk                            (clk_50m                   ),
    .ref_rst_n                          (sys_rst_n                 ),
    .cam_pclk                           (cam1_pclk                 ),
    .cam_vsync                          (cam1_vsync                ),
    .hdmi_vsync                         (hdmi_out_vsync            ),
    .cam_pclk_freq_hz                   (diag_cam_pclk_freq_hz     ),
    .cam_pclk_valid                     (diag_cam_pclk_valid       ),
    .cam_pclk_lost                      (diag_cam_pclk_lost        ),
    .cam_fps                            (diag_cam_fps              ),
    .cam_glitch_cnt                     (diag_cam_glitch_cnt       ),
    .cam_vsync_high_ns                  (diag_cam_vsync_high_ns    ),
    .cam_frame_period_ns                (diag_cam_frame_period_ns  ),
    .cam_vsync_lost                     (diag_cam_vsync_lost       ),
    .hdmi_fps                           (diag_hdmi_fps             ),
    .hdmi_glitch_cnt                    (diag_hdmi_glitch_cnt      ),
    .hdmi_vsync_high_ns                 (diag_hdmi_vsync_high_ns   ),
    .hdmi_frame_period_ns               (diag_hdmi_frame_period_ns ),
    .hdmi_vsync_lost                    (diag_hdmi_vsync_lost      ),
    .rate_valid                         (diag_rate_valid           )
);

endmodule


















//未优化的代码 -未使用XPM_cdc ----------------弃用---------------------------------
//未复位fifo 导致上板图像错乱 仿真不通过（busy一直为高）

// module  ov5640_ddr_hdmi
// (
//     input  wire                         sys_clk                    ,//系统时钟
//     input  wire                         sys_rst_n                  ,//系统复位，低电平有效
// //摄像头接口
//     output wire                         cam_rst_n                  ,//摄像1与2头复位信号，低电平有效
//     output wire                         cam_pwdn                   ,//摄像1与2头时钟选择信号
//     // output  wire            xclk,      //摄像头上板载了24MHZ晶振，直接使用 不由FPGA产生了
    
//     input  wire                         cam1_pclk                  ,//摄像1头数据像素时钟
//     input  wire                         cam1_vsync                 ,//摄像1头场同步信号
//     input  wire                         cam1_href                  ,//摄像1头行同步信号
//     input  wire          [   7: 0]      cam1_data                  ,//摄像1头数据
//     output wire                         sccb1_scl                  ,//摄像头1SCCB_SCL线
//     inout  wire                         sccb1_sda                  ,//摄像头1SCCB_SDA线
// //HDMI
//     output wire                         ddc_scl                    ,//hdmi芯片配置scl
//     inout  wire                         ddc_sda                    ,//hdmi芯片配置sda
//     output wire                         hdmi_out_clk               ,//hdmi输出时钟
//     output wire                         hdmi_out_rst_n             ,//hdmi复位
//     output wire                         hdmi_out_hsync             ,//hdmi输出行同步信号
//     output wire                         hdmi_out_vsync             ,//hdmi输出场同步信号
//     output wire          [  23: 0]      hdmi_out_rgb               ,//hdmi输出像素信息
//     output wire                         hdmi_out_de                ,//hdmi有效


// //DDR3接口
//     inout                [  31: 0]      ddr3_dq                    ,//数据线
//     inout                [   3: 0]      ddr3_dqs_n                 ,//数据选取脉冲差分信号
//     inout                [   3: 0]      ddr3_dqs_p                 ,//数据选取脉冲差分信号
//     output               [  14: 0]      ddr3_addr                  ,//地址线
//     output               [   2: 0]      ddr3_ba                    ,//bank线
//     output                              ddr3_ras_n                 ,//行使能信号，低电平有效
//     output                              ddr3_cas_n                 ,//列使能信号，低电平有效
//     output                              ddr3_we_n                  ,//写使能信号，低电平有效
//     output                              ddr3_reset_n               ,//ddr3复位
//     output               [   0: 0]      ddr3_ck_p                  ,//ddr3差分时钟
//     output               [   0: 0]      ddr3_ck_n                  ,//ddr3差分时钟
//     output               [   0: 0]      ddr3_cke                   ,//ddr3时钟使能信号
//     output               [   0: 0]      ddr3_cs_n                  ,//ddr3片选信号
//     output               [   3: 0]      ddr3_dm                    ,//ddr3掩码
//     output               [   0: 0]      ddr3_odt                    //odt阻抗

// );
// //------------------pll时钟--------------------
//     // wire                                clk_24m; 独立晶振 不由fpga提供 xclk
//     wire                                clk_50m                    ;
//     wire                                clk_100m                   ;
//     wire                                clk_200m                   ;
//     wire                                clk_74_25m                 ;
//     wire                                locked                    ;
// //--------------------camera------------------
//     assign                              cam_rst_n                   = 1                    ;
//     assign                              cam_pwdn                    = 0                    ;//如果要控制这个信号 需要遵守复位时序 数据手册里面有，我这里不需要控制我就直接把它置为0了
//     wire                                rst_n;
//     wire                                sys_init_done              ;
//     wire                                cam_cfg_done               ;
//     wire                                cam1_wr_en                 ;
//     wire                 [  15: 0]      cam1_data_out              ;//输出到写fifo的数据
// //------------------ddr3------------------------
//     wire                                ddr3_clk200m               ;//pll产生的200m时钟 输入系统时钟ddr3
//     wire                                ddr3_init_done             ;
//     wire                                ddr3_rst                   ;//ddr3系统复位信号
//     wire                                wrfifo_rst                 ;//写FIFO复位信号  清除fifo
    

//     wire                                rdfifo_rst                 ;


//     wire                                camera_done                ;

//    // ==================== 输出mig侧的时钟和复位 ====================
//     wire                                ui_clk                     ;//100MHZ DDR分频得到 输出
//     wire                                ui_clk_sync_rst            ;
// //---------------------------hdmi-----------------------
//     // wire                                vga_clk                    ;//视频输出时钟
//     reg                                 camera_done_toggle         ;//camera_done在100MHZ时钟域做了处理传过来的电平翻转信号
//     wire                 [  15: 0]      pix_data                   ;//读fifo数据输出
//     wire                                hdmi_cfg_done              ;
//     wire                 [  15: 0]      rgb                        ;//要做处理 填充为RGB888
//     wire                                hdmi_rd_en                 ;//读fifo使能
//     wire                 [  11: 0]      pix_y                      ;
//     wire                 [  11: 0]      pix_x                      ;

// //camera_down 做处理
// always@(posedge ui_clk or posedge ui_clk_sync_rst  )
// begin
//     if(ui_clk_sync_rst)
//         camera_done_toggle <= 1'b0;
//     else if(camera_done==1)
//         camera_done_toggle <= ~camera_done_toggle;
// end

// //填充RGB888 输出到HDMI编码芯片
// assign hdmi_out_rgb ={rgb[15:11],3'b0,
//                       rgb[10:5],2'b0,
//                       rgb[4:0],3'b0};

// //  hdmi_out_clk = vga_clk;
// assign hdmi_out_clk =clk_74_25m ;

// //hdmi_out_rst_n 
// wire hdmi_rst_n;
// assign hdmi_out_rst_n=sys_rst_n;

// //sys_init_done

// assign sys_init_done = (cam_cfg_done&&ddr3_init_done);

// //rst_n; 
// assign rst_n=sys_rst_n&ddr3_init_done&(!ui_clk_sync_rst)&(locked)  ;

// clk_wiz_0 instance_name
//    (
//     // Clock out ports
//     .clk_out1(clk_50m),       // output clk_out1
//     .clk_out2(clk_200m),     // output clk_out2
//     .clk_out3(clk_74_25m),     // output clk_out3
//     // Status and control signals
//     .reset(!sys_rst_n), // input reset
//     .locked(locked),       // output locked
//    // Clock in ports
//     .clk_in1(sys_clk));      // input clk_in1


                        
// ov5640_top ov5640_top_inst(
//     .sys_clk                            (clk_50m                   ),
//     .sys_rst_n                          (rst_n                     ),
// //   .camera_rst_n       (sys_rst_n & sys_init_done  ),  //复位信号
//     .sys_init_done                      (sys_init_done             ),
//     .ov5640_pclk                        (cam1_pclk                 ),
//     .ov5640_href                        (cam1_href                 ),
//     .ov5640_vsync                       (cam1_vsync                ),
//     .ov5640_data                        (cam1_data                 ),
//     .cfg_done                           (cam_cfg_done              ),
//     .sccb_scl                           (sccb1_scl                 ),
//     .sccb_sda                           (sccb1_sda                 ),
//     .ov5640_wr_en                       (cam1_wr_en                ),
//     .ov5640_data_out                    (cam1_data_out             ) 
   
// );

// hdmi_drvier hdmi_drvier_inst(
//     .sys_clk                            (clk_50m                   ),
//     .hdmi_rst_n                         (rst_n                     ),
//     .sys_rst_n                          (sys_rst_n                 ),
//     .vga_clk                            (clk_74_25m                ),
//     .camera_done_toggle                 (camera_done_toggle        ),
//     .pix_data                           (pix_data                  ),
//     .ddc_scl                            (ddc_scl                   ),
//     .ddc_sda                            (ddc_sda                   ),
//     .cfg_done                           (hdmi_cfg_done             ),
//     .rgb_valid                          (hdmi_out_de               ),
//     .rgb                                (rgb                       ),
//     .pix_data_req                       (hdmi_rd_en                ),
//     .hsync                              (hdmi_out_hsync            ),
//     .vsync                              (hdmi_out_vsync            ),
//     .pix_y                              (pix_y                     ),
//     .pix_x                              (pix_x                     ) 

// );

// ddr3_ctrl_2port ddr3_ctrl_2port_inst(
//     .ddr3_clk200m                       (clk_200m                  ),
//     .ddr3_rst                           (sys_rst_n&locked          ),
//     .ddr3_init_done                     (ddr3_init_done            ),//当DDR3初始化完成，并且mmcm locked也完成初始化时，才置1

//     .wr_clk                             (cam1_pclk                 ),
//     .din                                (cam1_data_out             ),
//     .wr_en                              (cam1_wr_en                ),
//     .wrfifo_rst                         (1'b0                      ),
//     .full                               (                          ),
//     .wr_data_count                      (                          ),

//     .rd_clk                             (clk_74_25m                ),
//     .rdfifo_rst                         (1'b0                      ),
//     .rd_en                              (hdmi_rd_en                ),
//     .dout                               (pix_data                  ),
//     .empty                              (                          ),
//     .rd_data_count                      (                          ),
//     // DDR3接口
//     .ddr3_addr                          (ddr3_addr                 ),// output [14:0]		ddr3_addr
//     .ddr3_ba                            (ddr3_ba                   ),// output [2:0]		ddr3_ba
//     .ddr3_cas_n                         (ddr3_cas_n                ),// output			    ddr3_cas_n
//     .ddr3_ck_n                          (ddr3_ck_n                 ),// output [0:0]		ddr3_ck_n
//     .ddr3_ck_p                          (ddr3_ck_p                 ),// output [0:0]		ddr3_ck_p
//     .ddr3_cke                           (ddr3_cke                  ),// output [0:0]		ddr3_cke
//     .ddr3_ras_n                         (ddr3_ras_n                ),// output			    ddr3_ras_n
//     .ddr3_reset_n                       (ddr3_reset_n              ),// output			    ddr3_reset_n
//     .ddr3_we_n                          (ddr3_we_n                 ),// output			    ddr3_we_n
//     .ddr3_dq                            (ddr3_dq                   ),// inout [31:0]		ddr3_dq
//     .ddr3_dqs_n                         (ddr3_dqs_n                ),// inout [3:0]		    ddr3_dqs_n
//     .ddr3_dqs_p                         (ddr3_dqs_p                ),// inout [3:0]		    ddr3_dqs_p
//     // .init_calib_complete                (init_calib_complete       ),// output			    init_calib_complete
//     .ddr3_cs_n                          (ddr3_cs_n                 ),// output [0:0]		ddr3_cs_n
//     .ddr3_dm                            (ddr3_dm                   ),// output [3:0]		ddr3_dm
//     .ddr3_odt                           (ddr3_odt                  ),// output [0:0]		ddr3_odt


//      // ==================== 输出mig侧的时钟和复位 ====================
//     .ui_clk                             (ui_clk                    ),//100MHZ DDR分频得到 输出
//     .ui_clk_sync_rst                    (ui_clk_sync_rst           ),
//        //==================== 实验接口 ====================
//     .w_done                             (camera_done               ) 
// );




// endmodule
