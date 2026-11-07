`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/18 09:16:35
// Design Name: HUKUAN
// Module Name: vga_ctrl
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


module vga_ctrl(
    input   wire            vga_clk     ,   //输入工作时钟,频率74.25MHz
    input   wire            hdmi_rst_n   ,   //输入复位信号,低电平有效
    input   wire    [15:0]  pix_data    ,   //输入像素点色彩信息

    output  wire    [11:0]  pix_x       ,   //输出VGA有效显示区域像素点X轴坐标
    output  wire    [11:0]  pix_y       ,   //输出VGA有效显示区域像素点Y轴坐标
    output  wire            hsync       ,   //输出行同步信号
    output  wire            vsync       ,   //输出场同步信号
    output  wire            pix_data_req  , //读使能请求
    output  wire    [15:0]  rgb           ,  //输出像素点色彩信息
    output  wire            rgb_valid     , //输出像素点色彩信息有效信号 de信号
    // 新增：一帧写入完成
    // 若来自其他时钟域，必须保持为高电平直到被可靠采到；
    // 不可直接输入其他时钟域的单周期窄脉冲。快时钟域-慢时钟域
   // input   wire            camera_done
   // 输入端口改为 camera_done_toggle
    input wire camera_done_toggle
    );
//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
////////////////////////    显示器适配列表   //////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////// 
//`define Resolution_480x272 1       //需要的时钟：9MHz
//`define Resolution_640x480 1       //需要的时钟：25.175MHz
//`define Resolution_800x480 1       //需要的时钟：33MHz
//`define Resolution_800x600 1       //需要的时钟：40MHz
//`define Resolution_1024x768 1      //需要的时钟：65MHz
 `define Resolution_1280x720 1      //需要的时钟：74.25MHz
//`define Resolution_1920x1080 1     //需要的时钟：148.5MHz
// `define Resolution_256x4 1         //需要的时钟：无所谓，仿真专用
//`define Resolution_256x2 1        //需要的时钟：无所谓，仿真专用
// `define Resolution_384x2 1
// `define Resolution_1280x2 1

`ifdef Resolution_480x272    
    `define H_Right_Border 0
    `define H_Front_Porch 2
    `define H_Sync_Time 41
    `define H_Back_Porch 2
    `define H_Left_Border 0
    `define H_Data_Time 480
    `define H_Total_Time 525
    `define V_Bottom_Border 0
    `define V_Front_Porch 2
    `define V_Sync_Time 10
    `define V_Back_Porch 2
    `define V_Top_Border 0
    `define V_Data_Time 272
    `define V_Total_Time 286
    
`elsif Resolution_640x480
	`define H_Total_Time  12'd800
	`define H_Right_Border  12'd8
	`define H_Front_Porch  12'd8
	`define H_Sync_Time  12'd96
	`define H_Data_Time 12'd640
	`define H_Back_Porch  12'd40
	`define H_Left_Border  12'd8
	`define V_Total_Time  12'd525
	`define V_Bottom_Border  12'd8
	`define V_Front_Porch  12'd2
	`define V_Sync_Time  12'd2
	`define V_Data_Time 12'd480
	`define V_Back_Porch  12'd25
	`define V_Top_Border  12'd8
	
`elsif Resolution_800x480
	`define H_Total_Time 12'd1056
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd40
	`define H_Sync_Time 12'd128
	`define H_Data_Time 12'd800
	`define H_Back_Porch 12'd88
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd525
	`define V_Bottom_Border 12'd8
	`define V_Front_Porch 12'd2
	`define V_Sync_Time 12'd2
	`define V_Data_Time 12'd480
	`define V_Back_Porch 12'd25
	`define V_Top_Border 12'd8

`elsif Resolution_800x600
	`define H_Total_Time 12'd1056
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd40
	`define H_Sync_Time 12'd128
	`define H_Data_Time 12'd800
	`define H_Back_Porch 12'd88
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd628
	`define V_Bottom_Border 12'd0
	`define V_Front_Porch 12'd1
	`define V_Sync_Time 12'd4
	`define V_Data_Time 12'd600
	`define V_Back_Porch 12'd23
	`define V_Top_Border 12'd0

`elsif Resolution_1024x768
	`define H_Total_Time 12'd1344
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd24
	`define H_Sync_Time 12'd136
	`define H_Data_Time 12'd1024
	`define H_Back_Porch 12'd160
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd806
	`define V_Bottom_Border 12'd0
	`define V_Front_Porch 12'd3
	`define V_Sync_Time 12'd6
	`define V_Data_Time 12'd768
	`define V_Back_Porch 12'd29
	`define V_Top_Border 12'd0

`elsif Resolution_1280x720
	`define H_Total_Time 12'd1650
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd110
	`define H_Sync_Time 12'd40
	`define H_Data_Time 12'd1280
	`define H_Back_Porch 12'd220
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd750
	`define V_Bottom_Border 12'd0
	`define V_Front_Porch 12'd5
	`define V_Sync_Time 12'd5
	`define V_Data_Time 12'd720
	`define V_Back_Porch 12'd20
	`define V_Top_Border 12'd0
		
`elsif Resolution_1920x1080
	`define H_Total_Time 12'd2200
	`define H_Right_Border 12'd0
	`define H_Front_Porch 12'd88
	`define H_Sync_Time 12'd44
	`define H_Data_Time 12'd1920
	`define H_Back_Porch 12'd148
	`define H_Left_Border 12'd0

	`define V_Total_Time 12'd1125
	`define V_Bottom_Border 12'd0
	`define V_Front_Porch 12'd4
	`define V_Sync_Time 12'd5
	`define V_Data_Time 12'd1080
	`define V_Back_Porch 12'd36
	`define V_Top_Border 12'd0	
	
`elsif Resolution_256x4
    // 仿照 1280x720 比例：水平方向按 256/1280=0.2 缩放，垂直方向保留最小合理消隐
    `define H_Total_Time      330     // 256 + 22(HFP) + 8(HS) + 44(HBP)
    `define H_Right_Border    0
    `define H_Front_Porch     22
    `define H_Sync_Time       8
    `define H_Data_Time       256
    `define H_Back_Porch      44
    `define H_Left_Border     0

    `define V_Total_Time      20      // 4 + 2(VFP) + 2(VS) + 12(VBP)
    `define V_Bottom_Border   0
    `define V_Front_Porch     2
    `define V_Sync_Time       2
    `define V_Data_Time       4
    `define V_Back_Porch      12
    `define V_Top_Border      0

`elsif Resolution_256x2
    // 水平方向：256 + 22 + 8 + 44
    `define H_Total_Time      330
    `define H_Right_Border    0
    `define H_Front_Porch     22
    `define H_Sync_Time       8
    `define H_Data_Time       256
    `define H_Back_Porch      44
    `define H_Left_Border     0

    // 垂直方向：2 + 2 + 2 + 12
    `define V_Total_Time      18
    `define V_Bottom_Border   0
    `define V_Front_Porch     2
    `define V_Sync_Time       2
    `define V_Data_Time       2
    `define V_Back_Porch      12
    `define V_Top_Border      0


`elsif Resolution_384x2
    // 仿照 1280x720 比例：水平方向按 384/1280 = 0.3 缩放
    // H_Sync=40*0.3≈12, H_Back_Porch=220*0.3≈66, H_Front_Porch=110*0.3≈33
    `define H_Total_Time      495     // 384 + 33 + 12 + 66
    `define H_Right_Border    0
    `define H_Front_Porch     33
    `define H_Sync_Time       12
    `define H_Data_Time       384
    `define H_Back_Porch      66
    `define H_Left_Border     0

    // 垂直方向：2 有效行 + 2 + 2 + 12
    `define V_Total_Time      18
    `define V_Bottom_Border   0
    `define V_Front_Porch     2
    `define V_Sync_Time       2
    `define V_Data_Time       2
    `define V_Back_Porch      12
    `define V_Top_Border      0

`elsif Resolution_1280x2
 
    `define H_Total_Time      1650
    `define H_Right_Border    0
    `define H_Front_Porch     110
    `define H_Sync_Time       40
    `define H_Data_Time       1280
    `define H_Back_Porch      220
    `define H_Left_Border     0

    `define V_Total_Time      18
    `define V_Bottom_Border   0
    `define V_Front_Porch     2
    `define V_Sync_Time       2
    `define V_Data_Time       2
    `define V_Back_Porch      12
    `define V_Top_Border      0
`endif


// `elsif Resolution_1280x720
// 	`define H_Total_Time 12'd1650
// 	`define H_Right_Border 12'd0
// 	`define H_Front_Porch 12'd110
// 	`defineH_Sync_ Time 12'd40
// 	`define H_Data_Time 12'd1280
// 	`define H_Back_Porch 12'd220
// 	`define H_Left_Border 12'd0

// 	`define V_Total_Time 12'd750
// 	`define V_Bottom_Border 12'd0
// 	`define V_Front_Porch 12'd5
// 	`define V_Sync_Time 12'd5
// 	`define V_Data_Time 12'd720
// 	`define V_Back_Porch 12'd20
// 	`define V_Top_Border 12'd0

//============================================================
// 有效显示区域边界
//============================================================
localparam H_START =
    `H_Sync_Time + `H_Back_Porch + `H_Left_Border;

localparam H_END =
    H_START + `H_Data_Time;

localparam V_START =
    `V_Sync_Time + `V_Back_Porch + `V_Top_Border;

localparam V_END =
    V_START + `V_Data_Time;

//============================================================
// 行、场计数器
//============================================================
reg [$clog2(`H_Total_Time)-1:0] h_cnt;
reg [$clog2(`V_Total_Time)-1:0] v_cnt;


// 两级同步 + 打一拍用于边沿检测
(* ASYNC_REG = "TRUE" *) reg camera_done_toggle_meta;
(* ASYNC_REG = "TRUE" *) reg camera_done_toggle_sync;
reg camera_done_toggle_sync_d;
reg frame_written;
reg display_started;

wire frame_start;
wire pix_req_window;

always @(posedge vga_clk or negedge hdmi_rst_n) begin
    if (!hdmi_rst_n) begin
        camera_done_toggle_meta   <= 1'b0;
        camera_done_toggle_sync   <= 1'b0;
        camera_done_toggle_sync_d <= 1'b0;
    end else begin
        camera_done_toggle_meta   <= camera_done_toggle;
        camera_done_toggle_sync   <= camera_done_toggle_meta;
        camera_done_toggle_sync_d <= camera_done_toggle_sync;
    end
end

// 检测 toggle 变化（上升沿或下降沿都算一次事件）
wire camera_done_event = camera_done_toggle_sync ^ camera_done_toggle_sync_d;

// 置位 frame_written，保持到复位
always @(posedge vga_clk or negedge hdmi_rst_n) begin
    if (!hdmi_rst_n)
        frame_written <= 1'b0;
    else if (camera_done_event)
        frame_written <= 1'b1;
end



// 一帧扫描开始，持续一个像素时钟。
// 此时还处于消隐区，距离第一个有效像素还有时间。
assign frame_start = (h_cnt == 0) && (v_cnt == 0);

// 只在帧边界允许首次启动。
// 后续持续读取，不因camera_done下降而停止。
always @(posedge vga_clk or negedge hdmi_rst_n)
begin
    if (!hdmi_rst_n)
        display_started <= 1'b0;
    else if (!display_started && frame_written && frame_start)
        display_started <= 1'b1;
end

//============================================================
// 行计数：始终运行，不受camera_done控制
//============================================================
always @(posedge vga_clk or negedge hdmi_rst_n)
begin
    if (!hdmi_rst_n)
        h_cnt <= 0;
    else if (h_cnt == `H_Total_Time - 1)
        h_cnt <= 0;
    else
        h_cnt <= h_cnt + 1'b1;
end

//============================================================
// 场计数：每行结束时更新
//============================================================
always @(posedge vga_clk or negedge hdmi_rst_n)
begin
    if (!hdmi_rst_n)
        v_cnt <= 0;
    else if (h_cnt == `H_Total_Time - 1) begin
        if (v_cnt == `V_Total_Time - 1)
            v_cnt <= 0;
        else
            v_cnt <= v_cnt + 1'b1;
    end
end

//============================================================
// 行、场同步：当前720p模式为正极性
//============================================================
assign hsync = (h_cnt < `H_Sync_Time);
assign vsync = (v_cnt < `V_Sync_Time);

//============================================================
// DE：始终保持标准显示时序
// 启动前输出黑色，而不是停止DE或同步信号。
//============================================================
assign rgb_valid =
    (h_cnt >= H_START) &&
    (h_cnt <  H_END)   &&
    (v_cnt >= V_START) &&
    (v_cnt <  V_END);

//============================================================
// 提前一拍的像素请求窗口
// 适用于FIFO读使能采样后，沿后输出数据的配置；
// pix_data路径不能再额外打一拍。
//============================================================
assign pix_req_window =
    (h_cnt >= H_START - 1) &&
    (h_cnt <  H_END   - 1) &&
    (v_cnt >= V_START)     &&
    (v_cnt <  V_END);

// 启动前不读FIFO；启动后按原来的提前一拍时序读取。
// 使用组合赋值，不额外增加请求延迟。
assign pix_data_req = display_started && pix_req_window;

//============================================================
// 请求对应的像素坐标
//============================================================
assign pix_x = pix_data_req
             ? (h_cnt - (H_START - 1))
             : 12'hfff;

assign pix_y = pix_data_req
             ? (v_cnt - V_START)
             : 12'hfff;

//============================================================
// RGB输出
// 启动前或消隐期间输出黑色。
//============================================================
assign rgb = (display_started && rgb_valid)
           ? pix_data
           : 16'h0000;

endmodule





//============================================================
// camera_done同步与首次启动控制  快时钟域-慢时钟域舍弃这个方案
//============================================================
/*(* ASYNC_REG = "TRUE" *) reg camera_done_meta;
(* ASYNC_REG = "TRUE" *) reg camera_done_sync;

reg frame_written;
reg display_started;

wire frame_start;
wire pix_req_window;

// 对持续电平进行两级同步。
// 注意：这不能保证捕获其他时钟域的单周期窄脉冲。
always @(posedge vga_clk or negedge hdmi_rst_n)
begin
    if (!hdmi_rst_n) begin
        camera_done_meta <= 1'b0;
        camera_done_sync <= 1'b0;
    end
    else begin
        camera_done_meta <= camera_done;
        camera_done_sync <= camera_done_meta;
    end
end

// 锁存“至少已经写完一帧”
// 置位后保持到复位，不是每帧重新清零。
always @(posedge vga_clk or negedge hdmi_rst_n)
begin
    if (!hdmi_rst_n)
        frame_written <= 1'b0;
    else if (camera_done_sync)
        frame_written <= 1'b1;
end */
















/* 未考虑跨模块之间的同步问题 弃用
    reg  [$clog2(`H_Total_Time)-1:0]  h_cnt;
    reg  [$clog2(`V_Total_Time)-1:0]  v_cnt;
   //输出行同步信号
    always@(posedge vga_clk or negedge hdmi_rst_n  )
    begin
        if(hdmi_rst_n == 1'b0)
        h_cnt <= 0;
        else if(h_cnt == `H_Total_Time-1)
        h_cnt <= 0;
        else
        h_cnt <= h_cnt + 1'b1;
    end
   assign hsync = (h_cnt<`H_Sync_Time)?1'b1:1'b0;
   //输出场同步信号
   always@(posedge vga_clk or negedge hdmi_rst_n  )
   begin
     if(hdmi_rst_n == 1'b0)
     v_cnt <= 0;
     else if(v_cnt == `V_Total_Time-1&&h_cnt == `H_Total_Time-1)
     v_cnt <= 0;
     else if(h_cnt == `H_Total_Time-1)
     v_cnt <= v_cnt + 1'b1;
   end
    assign vsync = (v_cnt<`V_Sync_Time)?1'b1:1'b0;

    //输出图像有效信号标志
    assign rgb_valid = ((h_cnt>=`H_Left_Border+`H_Back_Porch+`H_Sync_Time)&&(h_cnt<`H_Left_Border+`H_Back_Porch+`H_Sync_Time+`H_Data_Time)&&(v_cnt>=`V_Top_Border+`V_Back_Porch+`V_Sync_Time)&&(v_cnt<`V_Top_Border+`V_Back_Porch+`V_Sync_Time+`V_Data_Time))?1'b1:1'b0;

    //输出像素点色彩信息请求信号 提前一拍读fifo数据对齐VGA时序 rd_en延迟了一拍才会把读数据赋值给pix_data
    assign  pix_data_req = ((h_cnt>=`H_Left_Border+`H_Back_Porch+`H_Sync_Time-1)&&(h_cnt<`H_Left_Border+`H_Back_Porch+`H_Sync_Time+`H_Data_Time-1)&&(v_cnt>=`V_Top_Border+`V_Back_Porch+`V_Sync_Time)&&(v_cnt<`V_Top_Border+`V_Back_Porch+`V_Sync_Time+`V_Data_Time))?1'b1:1'b0;
   

    //输出像素点坐标
   assign  pix_x = (pix_data_req == 1'b1)
                ? (h_cnt - (`H_Left_Border+`H_Back_Porch+`H_Sync_Time-1)) : 12'hfff;
   assign  pix_y = (pix_data_req == 1'b1)
                ? (v_cnt - (`V_Top_Border+`V_Back_Porch+`V_Sync_Time)) : 12'hfff;
    //输出像素点色彩信息
    assign rgb = (rgb_valid==1)?pix_data:0;


endmodule*/
