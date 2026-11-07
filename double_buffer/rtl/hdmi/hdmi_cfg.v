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
