`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/01 12:45:02
// Design Name: HUKUAN
// Module Name: iic_shift_bit_copy 
// Project Name: 
// Target Devices:  STO可以单独 更加原子化
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


module iic_shift_bit_copy#(
    parameter CLK = 50000000,
              I2CLK =100000 
)(
//------------------全局信号------------------
    input                               clk                        ,
    input                               rst_n                      ,
//==命令控制端口
    input                [   5: 0]      iic_cmd                    ,
    input                               iic_start                  ,
    output reg                          iic_down                   ,
    output reg                          iic_busy                   ,

//----------协议接口-------
    input                [   7: 0]      iic_tx_data                ,
    output reg           [   7: 0]      iic_rx_data                ,
    output reg                          iic_ack                    ,//从机应答
    output reg                          ack_check_flag             ,//应答检查标日志
    output reg                          ack_gen_flag               ,//应答生成标志

//------------------IIC接口-----------------
    output reg                          iic_scl                    ,
    output reg                          iic_sdat_o                 ,
    output reg                          iic_sdat_t                 ,
    input                               iic_sdat_i                  
    );
    localparam                          DIV_MAX                     = (CLK/I2CLK/4)-1      ;
//命令
localparam 
		WR   = 6'b000001,   //写请求
		STA  = 6'b000010,   //起始位请求
		RD   = 6'b000100,   //读请求
		STO  = 6'b001000,   //停止位请求
		ACK  = 6'b010000,   //应答位请求
		NACK = 6'b100000;   //无应答请求

//7种状�??            
    reg                  [   6: 0]      current_state              ;
    reg                  [   6: 0]      next_state                 ;

 localparam
            IDLE      = 7'b0000_001,                                //空闲状态
             START   = 7'b0000_010,                                 //产生起始信号
            WRITE   = 7'b0000_100,                                  //写数据状态
             RDATA   = 7'b0001_000,                                 //读数据状态
            ACK_CHECK = 7'b0010_000,                                //检测应答状态
            ACK_GEN   = 7'b0100_000,                                //产生应答状态
            STOP   = 7'b1000_000;                                   //产生停止信号

//上升沿触发开始信号 高速系统下几乎都是边沿触发
    reg                  [   1: 0]      iic_start_sync             ;
    wire                                iic_start_r                ;
    reg                                 iic_start_r_r              ;
    always@(posedge clk or negedge rst_n)
        begin
            if(!rst_n)
                begin
                    iic_start_sync    <= 2'b00;
                end
                else begin
                    
                    iic_start_sync[0] <= iic_start;
                    iic_start_sync[1] <= iic_start_sync[0];
                end
                end
    assign iic_start_r = (iic_start_sync==2'b01)?1'b1:1'b0;
    always@(posedge clk or negedge rst_n)
        begin
            
            
        if(!rst_n)
            begin
                iic_start_r_r <= 1'b0;
            end
            else begin
                iic_start_r_r <= iic_start_r;
            end
     end
    //仿真的时候多写了个复�??



    //产生忙碌信号 忙碌信号 表示当前正在传输数据 不接受下�??次开始信�??
    always@(posedge clk or negedge rst_n)
        begin
            if(!rst_n)
                begin
                    iic_busy <= 1'b0;
                end
                else if(iic_down)
                        begin
                            iic_busy <= 1'b0;
                        end
                else if(iic_start_r_r)//第二拍单周期脉冲产生忙碌信号
                        begin
                            iic_busy <= 1'b1;
                        end
                end
                   

//上升沿锁存数�?? 目的是解决命令和数据在下降沿到来时，数据可能发生变化的问�?? 防止中�?�操作命令变换导致数据出�??
    reg                  [   5: 0]      iic_cmd_r                  ;
    reg                  [   7: 0]      iic_tx_data_r              ;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        iic_cmd_r <= 5'b00000;
        iic_tx_data_r <= 8'b00000000;
    end
    else if(iic_start_r&&!iic_busy)                                  //第一拍单周期脉冲锁存数据
        begin
            iic_cmd_r <= iic_cmd;
            iic_tx_data_r <= iic_tx_data;
        end
    end



//四分频计数器和位计数�??
    reg                  [$clog2(DIV_MAX+1)-1: 0]div_cnt                    ;
    reg                  [   4: 0]      bit_cnt                    ;
    reg                                 div_cnt_en                 ;
    wire                                div_max_flag               ;
    always@(posedge clk or negedge rst_n)
        begin
            if(!rst_n)
                begin
                    div_cnt <= 0;
                end
            else if(div_cnt_en)
                begin
                    if(div_cnt >= DIV_MAX)
                        begin
                            div_cnt <= 0;
                        end
                    else
                        begin
                            div_cnt <= div_cnt + 1'b1;
                        end
                end
            else
                div_cnt <= 0;
        end

    assign                              div_max_flag                = (div_cnt == DIV_MAX) ? 1'b1 : 1'b0;

    always @(posedge clk or negedge rst_n)
        begin
            if(!rst_n)
                bit_cnt <= 0;
                else if(div_max_flag)begin
                    
                if((current_state==ACK_CHECK)||(current_state==ACK_GEN)||(current_state==START)||(current_state==STOP))
                    begin
                        if(bit_cnt == 3)
                            bit_cnt <= 0;
                        else
                            bit_cnt <= bit_cnt + 1'b1;
                    end
                    
                else if((current_state==WRITE)||(current_state==RDATA))
                    begin
                        if(bit_cnt == 31)
                            bit_cnt <= 0;
                        else
                            bit_cnt <= bit_cnt + 1'b1;
                    end
                    end
                else
                    bit_cnt <= bit_cnt;
                    end
    //三段式状态机

    always@(posedge clk or negedge rst_n)
        begin
            if(!rst_n)
                current_state <= IDLE;
            else
                current_state <= next_state;
        end



 
//状�?�转�??
always@(*)begin
    case(current_state)
        IDLE:begin
            if(iic_start_r_r&&!iic_busy)
            begin
                if(iic_cmd_r&STA)
                    next_state=START;
                else if(iic_cmd_r&WR)
                    next_state=WRITE;
                else if(iic_cmd_r&RD)
                    next_state=RDATA;
                else if(iic_cmd_r&STO)
                    next_state=STOP;
                else
                    next_state=IDLE;
            end
            else
                  next_state=IDLE;
            end
        START:
            begin
                if((bit_cnt==3)&&div_max_flag)
                  begin
                    if(iic_cmd_r&WR)
                        next_state=WRITE;
                    else if(iic_cmd_r&RD)
                        next_state=RDATA;
                    else
                        next_state=IDLE;
                  end
                else
                    next_state=START;
            end
        WRITE:
            begin
                if((bit_cnt==31)&&div_max_flag)
                begin
                    next_state=ACK_CHECK;
                end
                else
                    next_state=WRITE;
            end
        ACK_CHECK:
            begin
                if((bit_cnt==3) &&div_max_flag)
                begin
                    if(iic_cmd_r&STO)
                        next_state=STOP;
                    else
                        next_state=IDLE;
                end
                else
                    next_state=ACK_CHECK;
            end
        RDATA:
            begin
                if((bit_cnt==31)&&div_max_flag)//调试的时候写�??7位了
                begin
                  next_state=ACK_GEN;   
                end
                else
                    next_state=RDATA;
            end
        ACK_GEN:
            begin
                if((bit_cnt==3)&&div_max_flag)
                begin
                    if(iic_cmd_r&STO)
                        next_state=STOP;
                    else
                        next_state=IDLE;
                end
                else
                    next_state=ACK_GEN;
            end    
        STOP:
            begin
                if((bit_cnt==3)&&div_max_flag)
                    next_state=IDLE;
                else
                    next_state=STOP;
            end
        default:
            next_state=IDLE;
    endcase
end


//状�?�输�??
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)begin
       iic_ack<=1'b1;
       iic_down<=1'b0;
       iic_rx_data<=0;
       div_cnt_en<=0;
       ack_check_flag<=0;
       ack_gen_flag<=0;
       iic_sdat_t<=1;
        iic_sdat_o        <= 1; //串行数据总线，默认两条线都为�?
       iic_scl<=1;
    end
    else
    case(current_state)
        IDLE:
            begin
                iic_ack<=1'b1;
                iic_down<=1'b0;
                div_cnt_en<=(next_state!=IDLE)?1'b1:1'b0;
                ack_check_flag<=0;
                ack_gen_flag<=0;
                iic_sdat_t<=0;
                // iic_scl<=1;
                // iic_sdat_o<=1;
            end
        START:
            begin
                case(bit_cnt)
                    0:begin
                        iic_sdat_t<=0;
                        iic_scl<=iic_scl;
                        iic_sdat_o<=1;//调试的时候改�??�??
                    end
                    1:begin
                        iic_scl<=1;
                        iic_sdat_o<=1;
                    end
                    2:begin
                        iic_sdat_o<=0;
                        iic_scl<=1;
                    end
                    3:begin
                        iic_scl<=0;
                        iic_sdat_o<=0;
                    end
                    default:
                    begin
                        iic_scl<=1;
                        iic_sdat_o<=1;
                    end
                endcase
                end
        WRITE:
            begin
                case(bit_cnt)
                0,4,8,12,16,20,24,28:begin
                    iic_sdat_t<=0;
                    iic_scl<=0;
                    iic_sdat_o<=iic_tx_data_r[7-bit_cnt[4:2]];
                end
                1,5,9,13,17,21,25,29:begin
                    iic_scl<=1;
                    iic_sdat_o<=iic_sdat_o;
                end
                2,6,10,14,18,22,26,30:begin
                    iic_scl<=1;
                    iic_sdat_o<=iic_sdat_o;
                end
                3,7,11,15,19,23,27,31:begin
                    iic_scl<=0;
                    iic_sdat_o<=iic_sdat_o;
                    
                end
                default:
                begin
                    iic_scl<=1;
                    iic_sdat_o<=1;
                    iic_sdat_t<=1;
                end
                endcase
            end
        RDATA:
            begin
                case(bit_cnt)
                0,4,8,12,16,20,24,28:begin
                    iic_scl<=0;
                    iic_sdat_t<=1;
                end
                1,5,9,13,17,21,25,29:begin
                    iic_scl<=1;
                end
                2,6,10,14,18,22,26,30:begin
                    iic_scl<=1;
                    if(div_max_flag) begin//调试出大问题 必须只读取一�?
                    iic_rx_data<={iic_rx_data[6:0],iic_sdat_i};
                end
                end
                3,7,11,15,19,23,27,31:begin
                    iic_scl<=0;
                end
                default:
                     iic_scl<=1;
                endcase
            end
        ACK_CHECK:
            begin
                case(bit_cnt)
                0:
                    begin
                        iic_scl<=0;
                        iic_sdat_t<=1;
                    end
                1:
                    begin
                        iic_scl<=1;
                    end
                2:
                    begin
                        iic_ack<=iic_sdat_i;
                        ack_check_flag<=1;//1写成0�??
                        iic_scl<=1;
                    end
                3:
                   begin
                       iic_scl<=0;
                       if(iic_cmd_r&STO)begin
                        iic_down<=0;
                       end
                       else if(div_cnt==DIV_MAX )begin
                        iic_down<=1;
                       end  
                       else  begin                           
                                iic_down<=0;                              
                          end
                                              
                   end
                   default:
                     begin
                        
                        iic_scl<=1;
                       
                     end 

                endcase
            end
        ACK_GEN:
            begin
                case(bit_cnt)
                0:
                    begin
                        iic_sdat_t<=0;
                        iic_scl<=0;
                        ack_gen_flag<=1;
                        if(iic_cmd_r&ACK)
                          iic_sdat_o<=0;
                        else if(iic_cmd_r&NACK)
                           iic_sdat_o<=1;
                        else 
                           iic_sdat_o<=1;
                    end
                1:
                    begin
                        iic_scl<=1;
                        iic_sdat_o<=iic_sdat_o;
                    end
                2:
                    begin
                        iic_scl<=1;
                        iic_sdat_o<=iic_sdat_o;
                    end
                3:
                    begin
                        iic_scl<=0;
                        iic_sdat_o<=1;//调试提前拉高
                        ack_gen_flag<=0;
                       if(iic_cmd_r&STO)begin
                        iic_down<=0;
                       end
                       else if(div_cnt==DIV_MAX )begin
                        iic_down<=1;
                       end  
                       else  begin                           
                                iic_down<=0;                              
                          end
                    end
                default:
                     begin
                          iic_scl<=1;
                        iic_sdat_o<=1;
                        ack_gen_flag<=0;
                     end
                endcase
                        
             end
        STOP:
            begin
                case(bit_cnt)
                0:
                    begin
                        iic_scl<=0;
                        iic_sdat_o<=0;
                        iic_sdat_t<=0;
                         iic_down  <=0; 
                        iic_ack       <= 1;
                        ack_check_flag <=0; 

                    end
                1:
                    begin
                        iic_scl<=1;
                        iic_sdat_o<=0;
                    end
                2:
                    begin
                        iic_scl<=1;
                        iic_sdat_o<=1;
                    end
                3:  
                    begin
                        iic_scl<=1;
                        iic_sdat_o<=1;
                        if(div_max_flag&&(div_cnt==DIV_MAX))begin
                        iic_down<=1;
                        end
                    end
                default:
                     begin
                          iic_scl<=1;
                        iic_sdat_o<=1;
                     end
                endcase
            end
                    
        default:
            begin
                iic_scl<=1;
                iic_sdat_o<=1;
                iic_down<=0;               
                iic_rx_data<=iic_rx_data;
                iic_ack<=iic_ack;
                iic_sdat_t <= iic_sdat_t;
                div_cnt_en<=div_cnt_en;
                ack_check_flag<=0;
                ack_gen_flag <= 0;

            end
    endcase

            end
                        


endmodule
