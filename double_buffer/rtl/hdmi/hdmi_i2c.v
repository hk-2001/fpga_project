`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/17 09:32:45
// Design Name: HUKUAN
// Module Name: hdmi_i2c
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


module hdmi_i2c(
    input  wire                         clk                        ,//系统时钟50MHZ 分频得到SCL时钟 100KB
    input  wire                         rst_n                      ,
    output wire                         cfg_done                   ,
    output wire                         sccb_scl                   ,
    inout  wire                         sccb_sda                    
   
    );

    wire                                cfg_start                  ;//output
    wire                                cfg_end                    ;//input
    wire                 [  31: 0]      cfg_data                   ;//output
    wire                                iic_sdat_i                  ;
    wire                                iic_sdat_o                  ;
    wire                                iic_sdat_t                  ;

 top_iic_copy top_iic_copy_inst(
    .clk                                (clk                       ),
    .rst_n                              (rst_n                     ),
//-----控制接口------
    .iic_rw                             (0                         ),
    .iic_start                          (cfg_start                 ),
    .byte_num                           (1                         ),
//-----标志�??------
    .iic_done                           (cfg_end                   ),
    .iic_fail                           (                          ),
//--------数据接口---------
    .reg_addr                           (cfg_data[23:8]            ),
    // SiI9134 寄存器地址为 8bit，add_mode=0
    .add_mode                           (0                         ),
    .device_addr                        (cfg_data[31:25]           ),
    .wr_data                            (cfg_data[7:0]             ),
    .wr_req                             (                          ),
    .rd_data                            (                          ),
    .rd_valid                           (                          ),
//---------IIC接口---------
    .iic_sdat_i                         (iic_sdat_i                 ),
    .iic_sdat_o                         (iic_sdat_o                 ),
    .iic_sdat_t                         (iic_sdat_t                 ),
    .iic_sclk                           (sccb_scl                  ) 
 );

//------------- hdmi_cfg_inst -------------
hdmi_cfg  hdmi_cfg_inst(

    .clk                                (clk                       ),//系统时钟,由iic模块传入
    .rst_n                              (rst_n                     ),//系统复位,低有效
    .cfg_end                            (cfg_end                   ),//单个寄存器配置完成

    .cfg_start                          (cfg_start                 ),//单个寄存器配置触发信号
    .cfg_data                           (cfg_data                  ),//ID,REG_ADDR,REG_VAL
    .cfg_done                           (cfg_done                  ) //寄存器配置完成
);



  IOBUF #(
    .DRIVE                              (12                        ),// 输出驱动强度
    .IBUF_LOW_PWR                       ("TRUE"                    ),// 
    .IOSTANDARD                         ("DEFAULT"                 ),// IO电平标准
    .SLEW                               ("SLOW"                    ) //
  ) IOBUF_inst (
    .O                                  (iic_sdat_i                ),// 输出到FPGA内部逻辑
    .IO                                 (sccb_sda                  ),// 
    .I                                  (iic_sdat_o                ),// 
    .T                                  (iic_sdat_t                ) // 
  );

endmodule
