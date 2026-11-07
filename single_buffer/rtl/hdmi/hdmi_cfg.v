`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/17 08:37:13
// Design Name: HUKUAN
// Module Name: hdmi_cfg
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

module hdmi_cfg(
    input wire  clk,
    input wire  rst_n,
    input wire  cfg_end,
    output reg cfg_start,
    output wire  [31:0]  cfg_data,
    output reg  cfg_done

    );

   parameter  REG_NUM= 7'd6 ;
    parameter  CNT_WAIT_MAX = 10'd1023;

    wire    [31:0]  cfg_data_reg[REG_NUM-1:0]   ;   //寄存器配置数据暂存
    reg     [6:0]   reg_num     ;   //配置寄存器个数
    reg     [9:0]   cnt_wait    ;   //寄存器配置等待计数器

    always@(posedge clk or negedge rst_n   )
    if(rst_n == 1'b0)
       cnt_wait <= 10'd0;
    else if(cnt_wait < CNT_WAIT_MAX)
       cnt_wait <= cnt_wait + 1'b1;

    always@(posedge clk or negedge rst_n   )
    if(rst_n == 1'b0)
       reg_num <= 7'd0;
    else if(cfg_end == 1'b1)
        reg_num<=reg_num + 1'b1;
    
    always@(posedge clk or negedge rst_n   )
    if(rst_n == 1'b0)
       cfg_start <= 1'b0;
       else if(cnt_wait == CNT_WAIT_MAX -1)
       cfg_start <= 1'b1;
       else if(cfg_end == 1'b1&& reg_num < (REG_NUM-1))
       cfg_start <= 1'b1;
       else
       cfg_start <= 0;
    
    always@(posedge clk or negedge rst_n   )
    if(rst_n == 1'b0)
       cfg_done <= 1'b0;
       else if(reg_num == (REG_NUM-1)&&cfg_end == 1'b1)
       cfg_done <= 1'b1;
    
    
    assign  cfg_data = (cfg_done == 1'b0)? cfg_data_reg[reg_num] : 32'd0;
   
//assign  cfg_data_reg[00]  =       {8'h12,  8'h80};
assign  cfg_data_reg[0]  ={8'h72,16'h08,8'h35};
assign  cfg_data_reg[1]  ={8'h7a,16'h2f,8'h00};
assign  cfg_data_reg[2]  ={8'h60,16'h05,8'h10};
assign  cfg_data_reg[3]  ={8'h60,16'h08,8'h05};
assign  cfg_data_reg[4]  ={8'h60,16'h09,8'h01};
assign  cfg_data_reg[5]  ={8'h60,16'h05,8'h04};


        
endmodule


















































//弃用导致我颜色不对劲的主要原因就是寄存器配置错了
   /*
    parameter  REG_NUM= 8'd72 ;
    parameter  CNT_WAIT_MAX = 10'd1023;

    wire    [31:0]  cfg_data_reg[REG_NUM-1:0]   ;   //寄存器配置数据暂存
    reg     [7:0]   reg_num     ;   //配置寄存器个数（72 条，8bit 计数）
    reg     [9:0]   cnt_wait    ;   //寄存器配置等待计数器

    always@(posedge clk or negedge rst_n   )
    if(rst_n == 1'b0)
       cnt_wait <= 10'd0;
    else if(cnt_wait < CNT_WAIT_MAX)
       cnt_wait <= cnt_wait + 1'b1;

    always@(posedge clk or negedge rst_n   )
    if(rst_n == 1'b0)
       reg_num <= 8'd0;
    else if(cfg_end == 1'b1)
        reg_num<=reg_num + 1'b1;

    always@(posedge clk or negedge rst_n   )
    if(rst_n == 1'b0)
       cfg_start <= 1'b0;
       else if(cnt_wait == CNT_WAIT_MAX -1)
       cfg_start <= 1'b1;
       else if(cfg_end == 1'b1&& reg_num < (REG_NUM-1))
       cfg_start <= 1'b1;
       else
       cfg_start <= 0;

    always@(posedge clk or negedge rst_n   )
    if(rst_n == 1'b0)
       cfg_done <= 1'b0;
       else if(reg_num == (REG_NUM-1)&&cfg_end == 1'b1)
       cfg_done <= 1'b1;


    assign  cfg_data = (cfg_done == 1'b0)? cfg_data_reg[reg_num] : 32'd0;



////////////////////////////////////////////////////////////////////////////////
// 0x72 页：系统/输入格式/PLL/时序（28 条）
////////////////////////////////////////////////////////////////////////////////
// 1. 复位所有模块
assign cfg_data_reg[0]  = {8'h72, 16'h0005, 8'h01};
// 2. 解除复位
assign cfg_data_reg[1]  = {8'h72, 16'h0005, 8'h00};
// 3. 输入格式：VSYNC/HSYNC 分离、24bit 总线、上升沿、[FIX-1] bit1=0 逐像素采样
assign cfg_data_reg[2]  = {8'h72, 16'h0008, 8'h1D};
assign cfg_data_reg[3]  = {8'h72, 16'h000C, 8'h00};
// [FIX-2] 0x0D 不再写入（原 0x00 是无效值，破坏 RGB 直通）
// 4. 背景色（蓝/绿/红）
assign cfg_data_reg[4]  = {8'h72, 16'h004B, 8'h00};
assign cfg_data_reg[5]  = {8'h72, 16'h004C, 8'h00};
assign cfg_data_reg[6]  = {8'h72, 16'h004D, 8'hFF};
// 5. HDMI 发送 PLL（与 74.25MHz 像素时钟匹配）
assign cfg_data_reg[7]  = {8'h72, 16'h0082, 8'h25};
assign cfg_data_reg[8]  = {8'h72, 16'h0083, 8'h19};
assign cfg_data_reg[9]  = {8'h72, 16'h0084, 8'h31};
assign cfg_data_reg[10] = {8'h72, 16'h0085, 8'h01};
// 6. 输入时序：DE 使能、正极性、消隐
assign cfg_data_reg[11] = {8'h72, 16'h0032, 8'h04};
assign cfg_data_reg[12] = {8'h72, 16'h0033, 8'h41};
assign cfg_data_reg[13] = {8'h72, 16'h0034, 8'h19};
// 7. 有效显示区：1280 × 720（与 vga_ctrl 720P 一致）
assign cfg_data_reg[14] = {8'h72, 16'h0036, 8'h00};
assign cfg_data_reg[15] = {8'h72, 16'h0037, 8'h05};   // 0x0500 = 1280
assign cfg_data_reg[16] = {8'h72, 16'h0038, 8'hD0};
assign cfg_data_reg[17] = {8'h72, 16'h0039, 8'h02};   // 0x02D0 = 720
assign cfg_data_reg[18] = {8'h72, 16'h003E, 8'h00};
assign cfg_data_reg[19] = {8'h72, 16'h0040, 8'h6E};
assign cfg_data_reg[20] = {8'h72, 16'h0041, 8'h00};
assign cfg_data_reg[21] = {8'h72, 16'h0044, 8'h29};
assign cfg_data_reg[22] = {8'h72, 16'h0045, 8'h00};
assign cfg_data_reg[23] = {8'h72, 16'h0046, 8'h05};
assign cfg_data_reg[24] = {8'h72, 16'h0047, 8'h06};
assign cfg_data_reg[25] = {8'h72, 16'h0048, 8'h30};
assign cfg_data_reg[26] = {8'h72, 16'h0049, 8'h00};
assign cfg_data_reg[27] = {8'h72, 16'h004A, 8'h3C};

////////////////////////////////////////////////////////////////////////////////
// 0x7A 页：HDMI 数据包 / AVI InfoFrame / Audio InfoFrame / 使能（44 条）
////////////////////////////////////////////////////////////////////////////////
assign cfg_data_reg[28] = {8'h7A, 16'h0001, 8'h02};
assign cfg_data_reg[29] = {8'h7A, 16'h0002, 8'h01};
assign cfg_data_reg[30] = {8'h7A, 16'h0003, 8'h00};
assign cfg_data_reg[31] = {8'h7A, 16'h0004, 8'h18};
assign cfg_data_reg[32] = {8'h7A, 16'h0005, 8'h00};
assign cfg_data_reg[33] = {8'h7A, 16'h0014, 8'h11};
assign cfg_data_reg[34] = {8'h7A, 16'h001D, 8'h40};
assign cfg_data_reg[35] = {8'h7A, 16'h0021, 8'h02};
assign cfg_data_reg[36] = {8'h7A, 16'h0022, 8'h2B};
assign cfg_data_reg[37] = {8'h7A, 16'h002F, 8'h01};
// AVI InfoFrame（显示器靠它识别 720P RGB）
assign cfg_data_reg[38] = {8'h7A, 16'h0040, 8'h82};
assign cfg_data_reg[39] = {8'h7A, 16'h0041, 8'h02};
assign cfg_data_reg[40] = {8'h7A, 16'h0042, 8'h0D};   // Y1Y0=00 = RGB 色彩空间
assign cfg_data_reg[41] = {8'h7A, 16'h0043, 8'h59};
assign cfg_data_reg[42] = {8'h7A, 16'h0044, 8'h11};
assign cfg_data_reg[43] = {8'h7A, 16'h0045, 8'h28};
assign cfg_data_reg[44] = {8'h7A, 16'h0046, 8'h00};
assign cfg_data_reg[45] = {8'h7A, 16'h0047, 8'h04};
assign cfg_data_reg[46] = {8'h7A, 16'h0048, 8'h00};
assign cfg_data_reg[47] = {8'h7A, 16'h0049, 8'h00};
assign cfg_data_reg[48] = {8'h7A, 16'h004A, 8'h00};
assign cfg_data_reg[49] = {8'h7A, 16'h004B, 8'hD1};
assign cfg_data_reg[50] = {8'h7A, 16'h004C, 8'h02};
assign cfg_data_reg[51] = {8'h7A, 16'h004D, 8'h00};
assign cfg_data_reg[52] = {8'h7A, 16'h004E, 8'h00};
assign cfg_data_reg[53] = {8'h7A, 16'h004F, 8'h01};
assign cfg_data_reg[54] = {8'h7A, 16'h0050, 8'h05};
assign cfg_data_reg[55] = {8'h7A, 16'h0051, 8'h00};
assign cfg_data_reg[56] = {8'h7A, 16'h0052, 8'h00};
// Audio InfoFrame
assign cfg_data_reg[57] = {8'h7A, 16'h0080, 8'h84};
assign cfg_data_reg[58] = {8'h7A, 16'h0081, 8'h01};
assign cfg_data_reg[59] = {8'h7A, 16'h0082, 8'h0A};
assign cfg_data_reg[60] = {8'h7A, 16'h0083, 8'h70};
assign cfg_data_reg[61] = {8'h7A, 16'h0084, 8'h01};
assign cfg_data_reg[62] = {8'h7A, 16'h0085, 8'h00};
assign cfg_data_reg[63] = {8'h7A, 16'h0086, 8'h00};
assign cfg_data_reg[64] = {8'h7A, 16'h0087, 8'h00};
assign cfg_data_reg[65] = {8'h7A, 16'h0088, 8'h00};
assign cfg_data_reg[66] = {8'h7A, 16'h0089, 8'h00};
assign cfg_data_reg[67] = {8'h7A, 16'h008A, 8'h00};
assign cfg_data_reg[68] = {8'h7A, 16'h008B, 8'h00};
assign cfg_data_reg[69] = {8'h7A, 16'h008C, 8'h00};
assign cfg_data_reg[70] = {8'h7A, 16'h008D, 8'h00};
// 最后一条：数据包/输出使能
assign cfg_data_reg[71] = {8'h7A, 16'h003E, 8'h33};

endmodule
*/