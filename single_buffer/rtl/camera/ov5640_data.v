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

//// 修改的地方：
//1.等待帧计数
//  之前每来一个像素时钟就 +1，导致 frame_cnt 在 10 个时钟后就到顶，
// 根本没起到"丢弃前 10 帧不稳定图像"的作用。这里改为按帧同步上升沿计数。
//////////////////////////////////////////////////////////////////////////////////


//==============================================================================
//我复位后出现每次图像拼接错乱 怀疑是帧同步去抖的问题 
//猜测1
// 帧同步去抖 —— 解决"复位后图像拼接错乱 / 一幅图像被打散"
//
// -----------------------------------------------------------------------------
// 为什么改（实测证据）:
//   频率计上板实测：cam1_vsync 上每秒有 【1885 个】干扰上升沿（cam_glitch_cnt），
//   而真实帧率只有 30fps —— 即每帧内约 63 个虚假"帧同步"。
//
//    pic_flag 直接取 vsync 上升沿，完全没有过滤：
//       assign pic_flag = (vsync_dly==0 && vsync==1);
//   → 毛刺让 frame_cnt 在 0.5ms 内就累加到 WAIT_TIME(10)
//     （正常应需 10 × 33.3ms = 333ms）
//   → pic_valid 在【毛刺】那一拍置位 → 数据从【帧中间】开始写入 DDR
//   → DDR 里存的是"从帧某点开始的连续像素流"
//   → HDMI 从地址 0 读 → 图像被打散 / 拼接错乱 / 分屏
//   → 每次复位毛刺相位不同 → 每次错位都不一样（正好吻合你的现象）
//   结论：就是改了之后也没有解决这个问题,我的拼接数据和写使能是由行信号决定的 所以帧同步即使不去抖也不会影响我的输出 因为行信号只会在真正的帧信号来临之后拉高 而且我的逻辑是拉高一次以后 有效位置就会一直有效，直到复位，只是告知了一个起点 后面就不会在依赖这个帧信号了 全都由行信号决定输出 所以图像拼接错乱跟这没有关系
// 不过我后面频率计数要得到有效的摄像头帧率必须帧去抖----------------------------------------------------------------------------
// 怎么改（与频率计同一思路，已被仿真和上板验证）:
//   vsync 高电平必须持续 >= VSYNC_MIN_CYCLES 个 pclk，才被确认为"真帧同步"。
//   判据是【脉冲宽度】，因为：
//       真实 vsync 脉宽：几十 us 起（OV5640 通常 4~10 行）
//       干扰毛刺脉宽  ：几 ns ~ 几十 ns
//   两者差几百倍最干净。
//
//   代价：帧起始标志比真实 vsync 上升沿晚约 VSYNC_MIN_CYCLES 个 pclk
//        （84MHz 下 100 拍 ≈ 1.19us），
//        而 vsync 之后到有效数据之间还有几十 us 的垂直消隐，影响为零。
//
//   资源：约 10 个 FF（在 cam1_pclk 域），比频率计第一版（68 个）小一个数量级，
//        不会像之前那样把 cam1_pclk 域 hold 打崩。
//==============================================================================


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
 // [新增] 帧同步去抖阈值
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
 wire            pic_flag    ;   //帧图像标志信号,每拉高一次,代表一帧完整图像【已去毛刺】

 reg  data_flag;
 reg  data_flag_r;
 reg  ov5640_vsync_dly    ;   //摄像头输入场同步信号打拍（保留，原逻辑用）

 //---------------------------------------------------------------------------
 // [新增] 帧同步宽度确认：真帧同步 vs 毛刺
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

//旧逻辑
//  always@(posedge ov5640_pclk or negedge camera_rst_n)begin
//     if(!camera_rst_n)begin
//         ov5640_vsync_dly <= 1'b0;
//     end
//     else
//        ov5640_vsync_dly <= ov5640_vsync;
//  end

 //---------------------------------------------------------------------------
 // 帧图像标志【去毛刺版】
 //   原：assign pic_flag = (vsync_dly==0 && vsync==1);----- 毛刺照单全收
 //   现：只有"被确认为宽脉冲"的 vsync 才产生一次上升沿
 //---------------------------------------------------------------------------
 assign pic_flag = vs_confirmed & ~vs_confirmed_d ;

//等待帧计数
// 之前代码每来一个像素时钟就 +1，导致 frame_cnt 在 10 个时钟后就到顶，
// 根本没起到"丢弃前 10 帧不稳定图像"的作用。这里改为按帧同步上升沿计数。
// [补充] 配合上面的去抖，现在这里的"10 帧"是真的 10 帧（约 333ms），
//        不再被毛刺快速顶满，能真正起到"丢掉前 10 帧不稳定图像"的作用。
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
