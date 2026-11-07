`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/18 11:15:58
// Design Name: HUKUAN
// Module Name: hdmi_drvier
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


module hdmi_drvier(
    input  wire                         sys_clk                    , //系统时钟50MHz
    input  wire                         hdmi_rst_n                 ,
    input  wire                         sys_rst_n                  ,
    input  wire                         vga_clk                    ,//vga时钟 频率74.25MHz
    input  wire                         camera_done_toggle         ,
    input  wire          [  15: 0]      pix_data                   ,
    output                              ddc_scl                    ,
    inout                               ddc_sda                    ,
    output                              cfg_done                   ,
    output                              rgb_valid                  ,//de
    output               [  15: 0]      rgb                        ,
    output                              pix_data_req               ,//读使能fifo
    output wire                         hsync                      ,
    output wire                         vsync                      ,
    output wire          [  11: 0]      pix_y                      ,
    output wire          [  11: 0]      pix_x                      
    // output     frame_begin//读fifo清零

    );
    hdmi_i2c hdmi_i2c_inst(
    .clk                                (sys_clk                   ),
    .rst_n                              (sys_rst_n                 ),
    .cfg_done                           (cfg_done                  ),
    .sccb_scl                           (ddc_scl                   ),
    .sccb_sda                           (ddc_sda                   ) 
    );
    vga_ctrl vga_ctrl_inst(
    .vga_clk                            (vga_clk                   ),
    .hdmi_rst_n                         (hdmi_rst_n                ),
    .pix_data                           (pix_data                  ),
    .pix_y                              (pix_y                     ),
    .pix_x                              (pix_x                     ),
    .hsync                              (hsync                     ),
    .vsync                              (vsync                     ),
    .pix_data_req                       (pix_data_req              ),
    .rgb                                (rgb                       ),
    .rgb_valid                          (rgb_valid                 ),
    .camera_done_toggle                 (camera_done_toggle         )
    );

endmodule
