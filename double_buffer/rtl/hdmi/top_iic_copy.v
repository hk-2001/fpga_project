`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/01 12:44:35
// Design Name: HUKUAN
// Module Name: top_iic_copy
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


module top_iic_copy#(
    parameter CLK = 50000000,
              I2CLK =100000 
)(
    input clk,
    input rst_n,
//-----控制接口------
    input iic_rw,
    input iic_start,
    input [4:0] byte_num,
//-----标志�??------
    output reg iic_done,
    output reg iic_fail,
//--------数据接口---------
    input [15:0] reg_addr,
    input add_mode,
    input [6:0] device_addr,
    input [7:0] wr_data,
    output reg wr_req,
    output reg [7:0] rd_data,
    output reg rd_valid,
//---------IIC接口---------
    input iic_sdat_i,
    output iic_sdat_o,
    output iic_sdat_t,
    output iic_sclk

    );
//模块连接参数
   reg  iic_bit_start;
   reg  [7:0] iic_tx_data;
   wire  iic_ack;
   wire  tran_down;
   wire ack_check_flag;
   wire ack_gen_flag;
   wire [7:0] iic_rx_data;  
   wire iic_busy;
   reg  [5:0] iic_cmd;

reg   [5:0 ]current_state;
reg   [5:0 ]next_state;


           
 localparam
            FAIL           = 6'b000_001,    //未接受到应答，失败状�?
            IDLE           = 6'b000_010,    //空闲状�??
            SEND_ADDR= 6'b000_100,    //发�?�地�?状�??
            READ_PHASE    = 6'b001_000,    //循环读数�?
            WRITE_PHASE   = 6'b010_000,    //循环写数�?
            DONE           = 6'b100_000;    //连续读�?�连续写状�?�结�?

//命令
localparam 
		WR   = 6'b000001,   //写请�?
		STA  = 6'b000010,   //起始位请�?
		RD   = 6'b000100,   //读请�?
		STO  = 6'b001000,   //停止位请�?
		ACK  = 6'b010000,   //应答位请�?
		NACK = 6'b100000;   //无应答请�?


//写入数据打两�?? ，防止亚稳�??
reg [7:0] wr_data_r;
reg [7:0] wr_data_r_r;
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        wr_data_r <= 8'b0;
        wr_data_r_r <= 8'b0;
    end
    else
    begin
        wr_data_r <= wr_data;
        wr_data_r_r <= wr_data_r;
    end
end
//边沿上升沿检测转单周期脉�??
reg [1:0] iic_sync;
wire iic_start_flag;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        iic_sync <= 2'b00;
    end
    else begin
    
       iic_sync[0] <= iic_start;
       iic_sync[1] <= iic_sync[0];
    end
end
assign iic_start_flag = (iic_sync==2'b01)?1'b1:1'b0;

//tran_done 信号三级打拍流水线操�??
reg  [2:0] reg_tran_down;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        reg_tran_down <= 3'b000;
    end
    else begin
        reg_tran_down[0] <= tran_down;
        reg_tran_down[1] <= reg_tran_down[0];
        reg_tran_down[2] <= reg_tran_down[1];
    end
end

//地址计数�??
reg  [1:0] send_addr_cnt;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
         send_addr_cnt <= 0;
    end
    else if(current_state==SEND_ADDR)
    begin
        if(tran_down)
            send_addr_cnt <= send_addr_cnt + 1'b1;
    end
    else
          send_addr_cnt <= 0;
end
//写读操作计数�??
reg [5:0] wr_rd_cnt;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        wr_rd_cnt <= 6'b000000;
    end
     else if(current_state==READ_PHASE)
    begin
        // if(wr_rd_cnt==byte_num+1)
        // wr_rd_cnt<=0;
        // else
        if(tran_down)
        wr_rd_cnt <= wr_rd_cnt + 1'b1;
    end
    else if(current_state==WRITE_PHASE)
    begin
        // if(wr_rd_cnt==byte_num)
        // wr_rd_cnt<=0;
        // else 
        if(tran_down)
        wr_rd_cnt <= wr_rd_cnt + 1'b1;
    end
   
    else
        wr_rd_cnt <= 0;
end
//三段式状态机
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        current_state <= IDLE;
    end
    else
     begin
       current_state <= next_state;
end
end

always@(*)
begin
    // if(!rst_n)
    // begin
    //     next_state = IDLE;
    // end
    // else
        case(current_state)
            IDLE:begin
                if(iic_done)
                    next_state = IDLE;
                else if(iic_start_flag)
                    next_state = SEND_ADDR;
                else
                    next_state = IDLE;
            end
            SEND_ADDR:begin
            //  if(ack_check_flag&&(iic_ack))
            //  begin
            //      next_state =FAIL;
            //  end
            //  else 
               case(add_mode)
                    1'b0:begin
                         if((send_addr_cnt==2)&&(reg_tran_down[1]))
                         begin
                            if(iic_rw)
                                next_state = READ_PHASE;
                            else
                                next_state = WRITE_PHASE;
                         end
                        else begin
                           next_state = SEND_ADDR;//调试问题
                        end
                         end
                    1'b1:begin
                         if((send_addr_cnt==3)&&(reg_tran_down[1]))
                         begin
                            if(iic_rw)
                                next_state = READ_PHASE;
                            else
                                next_state = WRITE_PHASE;
                         end
                        else begin
                            next_state = SEND_ADDR;
                        end
                        end
                    default: begin
                        next_state = SEND_ADDR;
                    end
                    endcase
            end
           
            READ_PHASE:begin
                // if((wr_rd_cnt==0)&&(ack_check_flag&&(iic_ack)))begin
                //   next_state = FAIL;
                // end else 
                if(wr_rd_cnt==(byte_num+1))
                  next_state = DONE;
                else
                  next_state=READ_PHASE;
            end

             WRITE_PHASE:begin
                // if(ack_check_flag&&(iic_ack))begin
                //   next_state = FAIL;
                // end else 
                if(wr_rd_cnt==(byte_num))
                  next_state = DONE;
                else
                  next_state=WRITE_PHASE;
            end
            DONE:begin
                next_state = IDLE;
            end
            FAIL:begin
                next_state = IDLE;
                end
            default:
                next_state = IDLE;
            endcase
end


always@(posedge clk or negedge rst_n)
begin
    if(!rst_n) begin
      iic_bit_start<=0;
      iic_tx_data<=0;
      iic_cmd<=0;
      iic_done<=0;
      iic_fail<=0;
    //   rd_data<=0;
      wr_req<=0;
    end
    else
    begin
        case(current_state)
            IDLE:begin
                iic_bit_start<=0;
                iic_tx_data<=0;
                iic_cmd<=0;
                iic_done<=0;
                iic_fail<=0;
                // rd_data<=0;
                wr_req<=0;
            end
           SEND_ADDR:
            begin
                case({send_addr_cnt, add_mode})
                3'b000:begin
                    iic_cmd<=STA|WR;
                    iic_bit_start<=1;
                    iic_tx_data<={device_addr,1'b0};
                    if(ack_check_flag)
                    begin
                        iic_cmd<=WR;
                        iic_bit_start<=0;
                    end
                end
                3'b010:begin
                    iic_cmd<=WR;
                    iic_bit_start<=1;
                    iic_tx_data<=reg_addr[7:0];

                    if(ack_check_flag)
                    begin
                        if(iic_rw)begin
                        
                           iic_cmd<=STA|WR;
                           iic_bit_start<=0;
                        end
                        else 
                        begin
                            iic_bit_start<=0;
                            if(byte_num==1)
                                iic_cmd<=WR|STO;
                            else
                                iic_cmd<=WR;
                        end
       
                    end
                end
                3'b001:begin
                    iic_cmd<=STA|WR;
                    iic_bit_start<=1;
                    iic_tx_data<={device_addr,1'b0};
                    if(ack_check_flag)
                    begin
                        iic_cmd<=WR;
                        iic_bit_start<=0;
                    end
                end
                3'b011:begin
                    iic_cmd<=WR;
                    iic_bit_start<=1;
                    iic_tx_data<=reg_addr[15:8];
                    if(ack_check_flag)
                    begin
                        iic_cmd<=WR;
                        iic_bit_start<=0;
                    end
                end
                3'b101:begin
                    iic_cmd<=WR;
                    iic_bit_start<=1;
                    iic_tx_data<=reg_addr[7:0];
                    if(ack_check_flag)
                    begin
                        if(iic_rw)begin
                        
                           iic_cmd<=STA|WR;
                           iic_bit_start<=0;
                        end
                        else 
                        begin
                            iic_bit_start<=0;
                            if(byte_num==1)
                                iic_cmd<=WR|STO;
                            else
                                iic_cmd<=WR;
                        end
       
                    end
                end
                default:begin
                    iic_cmd<=iic_cmd;
                    iic_bit_start<=iic_bit_start;
                    iic_tx_data<=iic_tx_data;
                end
                endcase
            end
            
            READ_PHASE:
            begin
                if(reg_tran_down[2])
                begin
                iic_bit_start<=1;
                end
                else if(wr_rd_cnt==0)
                begin
                    // iic_cmd<=STA|WR;
                    iic_tx_data<={device_addr,1'b1};
                    if(ack_check_flag)begin//少了个begin end
                    iic_bit_start<=0;
                       if(byte_num==1)
                       iic_cmd<=RD|NACK|STO;
                       else
                       iic_cmd<=RD|ACK;
                    end
                    // iic_bit_start<=0;
                  
                end
                else if(wr_rd_cnt!=0&&(wr_rd_cnt<(byte_num-1)))
                begin
                    iic_cmd<=RD|ACK;
                    iic_bit_start<=0;
                end 
                else if((wr_rd_cnt==(byte_num-1))&&(ack_gen_flag==1))
                begin
                    iic_cmd<=RD|NACK|STO;
                    iic_bit_start<=0;
                end
                else begin
                iic_cmd<=iic_cmd;//
                iic_bit_start<=0;  
                end 
            end
            WRITE_PHASE:
            begin
                if(reg_tran_down[2])
                begin
                iic_bit_start<=1;
                iic_tx_data<=wr_data_r_r;
                // iic_cmd<=WR|STO;
                end
                else if((wr_rd_cnt<(byte_num-1))&&tran_down)begin
                  wr_req<=1;
                  if(wr_rd_cnt<(byte_num-2))
                  begin
                   iic_cmd<=WR;
                //    iic_bit_start<=0;
                  end
                  else if(wr_rd_cnt==(byte_num-2))
                  begin
                    iic_cmd<=WR|STO;
                    // iic_bit_start<=0;
                  end
                end
                else begin //调试忘记加begin end
                    iic_cmd<=iic_cmd;//调试时清零了
                    iic_bit_start<=0; 
                    wr_req<=0;   
                end                           
            end
            DONE:
            begin
                iic_cmd<=0;
                iic_bit_start<=0;
                iic_done<=1;
                // iic_fail<=0;
                // wr_req<=0;
            end
            FAIL:
            begin
                iic_done<=1;
                iic_fail<=1;
                 iic_bit_start<=0;
                 iic_cmd<=0;
            end
            default:
            begin
                iic_done<=0;
                            wr_req<=0;
                            iic_fail<=0;
                            iic_cmd<=6'b0;
            //               iic_bit_start<=0;
                            iic_tx_data<=8'b0;
            end
        endcase
    end
end

//单独处理输出和有�??
always@(posedge clk)  
begin
    if(!rst_n)
    begin
        rd_data<=0;
        rd_valid<=0;
    end
    if((wr_rd_cnt!=0)&&(current_state==READ_PHASE)&&(tran_down==1))
    begin
        rd_data<=iic_rx_data;
        rd_valid<=tran_down;
    end
    else
    begin
        rd_data<=rd_data;
        rd_valid<=0;
    end
end                  

iic_shift_bit_copy u_iic_shift_bit_copy(
//------------------全局信号------------------
    .clk                                (clk                        ), // (input)
    .rst_n                              (rst_n                     ), // (input)
//==命令控制端口
    .iic_cmd                            (iic_cmd                   ), // (input)
    .iic_start                          (iic_bit_start               ), // (input)
    .iic_down                           (tran_down                  ), // (input)output)
    .iic_busy                           (iic_busy                  ), // (output)
//----------协议接口-------
    .iic_tx_data                        (iic_tx_data               ), // (input)
    .iic_rx_data                        (iic_rx_data               ), // (output)
    .iic_ack                            (iic_ack                   ), // (output)// 从机应答
    .ack_check_flag                     (ack_check_flag            ), // (output)// 应答�??查标�??
    .ack_gen_flag                       (ack_gen_flag              ), // (output)// 应答生成标志
//------------------IIC接口-----------------
    .iic_scl                            (iic_sclk                   ), // (output)
    .iic_sdat_o                         (iic_sdat_o               ), // (output)
    .iic_sdat_t                         (iic_sdat_t               ), // (output)
    .iic_sdat_i                         (iic_sdat_i                ) // (input)
);
           
       
// IOBUF #(
//      .DRIVE                              (12                        ),// 输出驱动强度
//      .IBUF_LOW_PWR                       ("TRUE"                    ),// 输入缓冲器低功�?�模�??
//      .IOSTANDARD                         ("DEFAULT"                 ),// IO电平标准
//      .SLEW                               ("SLOW"                    ) // 压摆率控�??
//  ) IOBUF_inst (
//      .O                                  (iic_sdat_i                    ),// 输出到FPGA内部逻辑
//      .IO                                 (iic_sda                       ),// 双向外部引脚（接顶层port�??
//      .I                                  (iic_sdat_o                   ),// 从FPGA内部�??
//      .T                                  (iic_sdat_t                   ) // 三�?�控�??
//  );







endmodule
