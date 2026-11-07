
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
    // 彩条测试开关：1=输出8色竖彩条(绕过摄像头/DDR)，0=正常显示
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
    // 由 xpm_rst_sync 产生的各时钟域同步释放复位（低有效）
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

//==================== 频率/帧率测量 ====================
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

// 8 色竖彩条（按 pix_x 分段），COLOR_TEST=1 时输出
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

// MIG sys_rst 低有效：PLL 锁定且外部复位释放后输出高电平
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

//==================== 复位同步 ====================
// 用 Xilinx XPM_CDC 原语 xpm_cdc_async_rst（异步断言、同步释放）为每个时钟域生成同步释放复位。
// 两个异步 FIFO(wr/rd_ddr3_fifo) 的复位保持原样、不经过本模块——FIFO Generator IP 内部已用
// xpm_cdc_sync_rst 完成复位同步，并提供 wr_rst_busy / rd_rst_busy 握手。
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
    .sys_rst_n                          (rst_n_cfg                 ),// 50MHz 域同步释放复位
    .camera_rst_n                       (rst_n_cam                 ),// 84MHz 域同步释放复位
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
    .hdmi_rst_n                         (rst_n_vga                 ),// 74.17MHz 域同步释放复位
    .sys_rst_n                          (rst_n_cfg                 ),// 50MHz 域同步释放复位
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

// FIFO 复位：上电/复位时清空 FIFO 残余像素
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

ddr3_ctrl_2port #(
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              )
) ddr3_ctrl_2port_inst(
    .ddr3_clk200m                       (clk_200m                  ),
    .ddr3_rst                           (ddr3_rst_n                ),
    .ddr3_init_done                     (ddr3_init_done            ),//当DDR3初始化完成，并且mmcm locked也完成初始化时，才置1

    .wr_clk                             (cam1_pclk                 ),
    .din                                (cam1_data_out             ),
    .wr_en                              (cam1_wr_en                ),
    .wrfifo_rst                         (wrfifo_rst_s              ),// 复位时清空写FIFO
    .full                               (                          ),
    .wr_data_count                      (                          ),

    .rd_clk                             (clk_74_25m                ),
    .rdfifo_rst                         (rdfifo_rst_s              ),// 复位时清空读FIFO
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

//==================== 频率/帧率测量模块 ====================
// 纯观测模块，只读信号不接入数据通路。参考时钟用 clk_50m（与 sys_clk 同频）。
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
