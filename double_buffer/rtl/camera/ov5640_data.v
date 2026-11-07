`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2026/09/19 09:46:34
// Design Name:HUKUAN
// Module Name: ov5640_data
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


//////////////////////////////////////////////////////////////////////////////////
module ov5640_data(
  input wire ov5640_pclk,
  input wire camera_rst_n,
  input wire ov5640_vsync,
  input wire ov5640_href,
  input wire [7:0] ov5640_data,

  //写fifo
  output wire ov5640_wr_en ,
  output wire [15:0] ov5640_data_out

    );
 parameter [3:0] WAIT_TIME = 4'd10 ;

 //---------------------------------------------------------------------------
 // 帧同步去抖阈值
 //   vsync 高电平必须持续 >= 该值个 pclk 才被确认为真帧同步
 //   84MHz 下：100 拍 ≈ 1.19us
 //     真实 vsync（几十 us 起）→ 必定通过
 //     干扰毛刺（几 ns~几十 ns）→ 必定被拒
 //   调大更保险，调小响应更快；若画面仍错乱可试 200。
 //---------------------------------------------------------------------------
 parameter [7:0] VSYNC_MIN_CYCLES = 8'd100 ;

 reg  [7:0]  ov5640_data_reg;

 reg  [4:0] frame_cnt;
 reg  pic_valid;
 reg  [15:0] data_out_reg;
 wire            pic_flag    ;   //帧图像标志信号,每拉高一次,代表一帧完整图像

 reg  data_flag;
 reg  data_flag_r;
 reg  ov5640_vsync_dly    ;   //摄像头输入场同步信号打拍

 //---------------------------------------------------------------------------
 // 帧同步宽度确认：vsync 高电平持续 >= VSYNC_MIN_CYCLES 才确认为真帧同步
 //---------------------------------------------------------------------------
 reg  [7:0]  vs_high_cnt       ;   // 当前 vsync 高电平已持续的 pclk 数
 reg         vs_confirmed      ;   // 本段 vsync 已被确认为真帧同步
 reg         vs_confirmed_d    ;   // 打一拍，用于取上升沿

 always @(posedge ov5640_pclk or negedge camera_rst_n) begin
    if (!camera_rst_n) begin
        vs_high_cnt    <= 8'd0;
        vs_confirmed   <= 1'b0;
        vs_confirmed_d <= 1'b0;
    end
    else begin
        vs_confirmed_d <= vs_confirmed;
        if (!ov5640_vsync) begin                    // 低电平：本段结束，清除确认
            vs_high_cnt  <= 8'd0;
            vs_confirmed <= 1'b0;
        end
        else if (!vs_confirmed) begin               // 高电平且本段尚未确认
            if (vs_high_cnt == VSYNC_MIN_CYCLES)
                vs_confirmed <= 1'b1;               // 宽度够了 → 确认为真帧同步
            else
                vs_high_cnt <= vs_high_cnt + 1'b1;
        end
    end
 end

 always@(posedge ov5640_pclk or negedge camera_rst_n)begin
    if(!camera_rst_n)begin
        ov5640_vsync_dly <= 1'b0;
    end
    else
       ov5640_vsync_dly <= ov5640_vsync;
 end

 //---------------------------------------------------------------------------
 // 帧图像标志：只有被确认为宽脉冲的 vsync 才产生一次上升沿
 //---------------------------------------------------------------------------
 assign pic_flag = vs_confirmed & ~vs_confirmed_d ;

 //等待帧计数：按帧同步上升沿计数，丢弃前 WAIT_TIME 帧不稳定图像
 always@(posedge ov5640_pclk or negedge camera_rst_n)begin
    if(!camera_rst_n)begin
        frame_cnt <= 5'd0;
    end
    else if(pic_flag && (frame_cnt < WAIT_TIME))begin
        frame_cnt <= frame_cnt + 1'b1;
    end
end

//帧有效
always@(posedge ov5640_pclk or negedge camera_rst_n)begin
    if(!camera_rst_n)begin
        pic_valid <= 1'b0;
    end
    else if((frame_cnt == WAIT_TIME)&&(pic_flag == 1'b1))begin
        pic_valid <= 1'b1;
    end
    else
       pic_valid <= pic_valid;
end

//输出16位缓存图像数据
always@(posedge ov5640_pclk or negedge camera_rst_n)begin
    if(!camera_rst_n)begin
         data_flag<=1'b0;
        data_out_reg <= 0;
        ov5640_data_reg <= 0;
    end
    else if(ov5640_href==1)
    begin
         data_flag<=!data_flag;
         data_out_reg <= data_out_reg;
         ov5640_data_reg <= ov5640_data;
      if(data_flag==1)
         data_out_reg <= {ov5640_data_reg,ov5640_data};
       else
         data_out_reg <= data_out_reg;
    end
    else begin
        data_flag<=1'b0;
        data_out_reg <= data_out_reg;
        ov5640_data_reg <= 0;
    end
end

//标志信号打拍 对齐data_out_reg
always@(posedge ov5640_pclk or negedge camera_rst_n)begin
    if(!camera_rst_n)begin
      data_flag_r<=0;
    end
    else
      data_flag_r<=data_flag;
end

//写fifo使能信号
assign ov5640_wr_en=(pic_valid==1'b1)?data_flag_r:1'b0;

//写数据
assign ov5640_data_out =(pic_valid==1'b1)?data_out_reg:1'b0;


endmodule
