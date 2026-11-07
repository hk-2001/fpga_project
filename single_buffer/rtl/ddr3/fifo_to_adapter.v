`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/13 08:51:28
// Design Name: HUKUAN
// Module Name: fifo_to_adapter
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



module fifo_axi4_adapter#(
    parameter                           FIFO_DW                     = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit
    parameter                           FIFO_ADDR_WIDTH             = 8                    ,
    // ==================== 地址与数据参数 ====================
  
    parameter                           BUF_A_BEGIN                 = 32'h0100_0000        ,//缓存A基地址
    // parameter                           BUF_B_BEGIN                 = 32'h0120_0000        ,//缓存B基地址
    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           CAMERA_AXI_ID               = 0                    ,
    parameter                           AXI_BURST_LEN               = 31                   ,


    // ==================== AXI 固定协议参数 ====================
    parameter                           AXI_ARBURST_INCR            = 2'b01                ,
    parameter                           AXI_ARLOCK_NORMAL           = 1'b0                 ,
    parameter                           AXI_ARCACHE_DEVICE_NON_BUF  = 4'b0000              ,
    parameter                           AXI_ARPROT_UNPRIV_SECURE    = 3'b000               ,
    parameter                           AXI_ARQOS_DEFAULT           = 4'b0000              ,
    parameter                           AXI_ARREGION_DEFAULT        = 4'b0000              ,
    parameter                           AXI_RRESP_OKAY              = 2'b00                ,

    parameter                           AXI_AWBURST_INCR            = 2'b01                ,
    parameter                           AXI_AWLOCK_NORMAL           = 1'b0                 ,
    parameter                           AXI_AWCACHE_DEVICE_NON_BUF  = 4'b0000              ,
    parameter                           AXI_AWPROT_UNPRIV_SECURE    = 3'b000               ,
    parameter                           AXI_AWQOS_DEFAULT           = 4'b0000              ,
    parameter                           AXI_AWREGION_DEFAULT        = 4'b0000              ,
    parameter                           AXI_BRESP_OKAY              = 2'b00                ,
    parameter                           AXI_WSTRB_ALL_VALID         = 1'b1                 ,
    parameter                           AXI_RESET_POLARITY          = 1'b1                 ,

    // ==================== 有关输出的图像信息 ====================
    parameter                           IMAGE_WIDTH                 = 1280                 ,//图片宽度
    parameter                           IMAGE_HEIGHT                = 720                  
)(
    //全局信号
    input                               ui_clk                     ,
    input                               reset                      ,
    //写fifo接口端
    input                               wr_clk                     ,
    input  wire          [  15: 0]      din                        ,
    input  wire                         wr_en                      ,
    input wire                          wrfifo_rst                 ,
    output wire                         full                       ,
    output wire          [  10: 0]      wr_data_count              ,
    // output wire                         wr_rst_busy                ,
    //读fifo接口端
    input  wire                         rd_clk                     ,
    input wire                          rdfifo_rst                 ,
    input  wire                         rd_en                      ,
    output wire          [  15: 0]      dout                       ,
    output wire                         empty                      ,
    output wire          [  10: 0]      rd_data_count              ,
    // output wire                         rd_rst_busy                ,
    //fifo_to_axi4接口
    //写地址通道
    output               [AXI_ID_WIDTH-1: 0]m_axi_awid             ,
    output               [AXI_ADDR_WIDTH-1: 0]m_axi_awaddr         ,
    output               [   7: 0]      m_axi_awlen                ,
    output               [   2: 0]      m_axi_awsize               ,
    output               [   1: 0]      m_axi_awburst              ,
    output               [   0: 0]      m_axi_awlock               ,
    output               [   3: 0]      m_axi_awcache              ,
    output               [   2: 0]      m_axi_awprot               ,
    output               [   3: 0]      m_axi_awqos                ,
    output               [   3: 0]      m_axi_awregion             ,
    output                              m_axi_awvalid              ,
    input                               m_axi_awready              ,
    //写数据通道
    output               [AXI_DATA_WIDTH-1: 0]m_axi_wdata          ,
    output               [AXI_DATA_WIDTH/8-1: 0]m_axi_wstrb        ,
    output                              m_axi_wlast                ,
    output                              m_axi_wvalid               ,
    input                               m_axi_wready               ,
     // -------------------------------------------------------------------------
    // AXI 写响应通道：仅 BID 匹配且 BRESP 成功才推进正常完成流程。
    // -------------------------------------------------------------------------
    input                [AXI_ID_WIDTH-1: 0]m_axi_bid              ,
    input                [   1: 0]      m_axi_bresp                ,
    input                               m_axi_bvalid               ,
    output                              m_axi_bready               ,
  
  // -------------------------------------------------------------------------
    // 帧完成输出：直接连接 w_brust_complete，无延迟链；按成功 B 响应数量定义帧边界。
    // -------------------------------------------------------------------------
    output                              camera_w_done              ,
    //axi4 to fifo
    // AXI 读地址通道：ARVALID 与 ARREADY 同时为高时握手。
    output               [AXI_ID_WIDTH-1: 0]m_axi_arid             ,
    output               [AXI_ADDR_WIDTH-1: 0]m_axi_araddr         ,
    output               [   7: 0]      m_axi_arlen                ,
    output               [   2: 0]      m_axi_arsize               ,
    output               [   1: 0]      m_axi_arburst              ,
    output               [   0: 0]      m_axi_arlock               ,
    output               [   3: 0]      m_axi_arcache              ,
    output               [   2: 0]      m_axi_arprot               ,
    output               [   3: 0]      m_axi_arqos                ,
    output               [   3: 0]      m_axi_arregion             ,
    output                              m_axi_arvalid              ,
    input                               m_axi_arready              ,
    // AXI 读数据通道：RVALID 与 RREADY 同时为高时接收一拍。
    input                [AXI_ID_WIDTH-1: 0]m_axi_rid              ,
    input                [AXI_DATA_WIDTH-1: 0]m_axi_rdata          ,
    input                [   1: 0]      m_axi_rresp                ,
    input                               m_axi_rlast                ,
    input                               m_axi_rvalid               ,
    output                              m_axi_rready               
 // r_done：AXI 帧接收完成，不是 FIFO 最后一拍写入完成。
    // output                              r_done                     
    );
    //参数接口定义
    //写fifo参数
    //  wire rd_clk_inst;
    wire                 [ 127: 0]      dout_inst                  ;
    wire                                empty_inst                 ;
    wire                 [   7: 0]      rd_data_count_inst         ;
    wire                                rd_rst_busy_inst0          ;
    wire                                wr_rst_busy_inst0          ;
    wire                                rd_en_inst                 ;
     //读fifo参数
    //  wire wr_clk_inst;
    wire                 [ 127: 0]      din_inst                   ;
    wire                                full_inst                  ;
    wire                 [   7: 0]      wr_data_count_inst         ;
    wire                                wr_rst_busy_inst1          ;
    wire                                rd_rst_busy_inst1          ;
    wire                                wr_en_inst                 ;
    
    //调用底层模块
    //异步写fifo
wr_ddr3_fifo wr_ddr3_fifo_inst (
    .rst                                (wrfifo_rst                ),// input wire rst
    .wr_clk                             (wr_clk                    ),// input wire wr_clk
    .rd_clk                             (ui_clk                    ),// input wire rd_clk
    .din                                (din                       ),// input wire [15 : 0] din
    .wr_en                              (wr_en                     ),// input wire wr_en
    .rd_en                              (rd_en_inst                ),// input wire rd_en
    .dout                               (dout_inst                 ),// output wire [127 : 0] dout
    .full                               (full                      ),// output wire full
    .empty                              (empty_inst                ),// output wire empty
    .rd_data_count                      (rd_data_count_inst        ),// output wire [7 : 0] rd_data_count
    .wr_data_count                      (wr_data_count             ),// output wire [10 : 0] wr_data_count
    .wr_rst_busy                        (wr_rst_busy_inst0         ),// output wire wr_rst_busy
    .rd_rst_busy                        (rd_rst_busy_inst0         ) // output wire rd_rst_busy
);

rd_ddr3_fifo rd_ddr3_fifo_inst (
    .rst                                (rdfifo_rst                ),// input wire rst
    .wr_clk                             (ui_clk                    ),// input wire wr_clk
    .rd_clk                             (rd_clk                    ),// input wire rd_clk
    .din                                (din_inst                  ),// input wire [127 : 0] din
    .wr_en                              (wr_en_inst                ),// input wire wr_en
    .rd_en                              (rd_en                     ),// input wire rd_en
    .dout                               (dout                      ),// output wire [15 : 0] dout
    .full                               (full_inst                 ),// output wire full
    .empty                              (empty                     ),// output wire empty
    .rd_data_count                      (rd_data_count             ),// output wire [12 : 0] rd_data_count
    .wr_data_count                      (wr_data_count_inst        ),// output wire [9 : 0] wr_data_count
    .wr_rst_busy                        (wr_rst_busy_inst1         ),// output wire wr_rst_busy
    .rd_rst_busy                        (rd_rst_busy_inst1         ) // output wire rd_rst_busy
);

fifo_to_axi4#(
    .BUF_A_BEGIN                        (BUF_A_BEGIN               ),
    // .BUF_B_BEGIN                        (BUF_B_BEGIN               ),

    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH            ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH            ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH              ),
    .AXI_ID                             (CAMERA_AXI_ID             ),//每个master的ID不同，需要差异化

    .AXI_BURST_LEN                      (AXI_BURST_LEN             ),
    .FIFO_ADDR_WIDTH                    (FIFO_ADDR_WIDTH           ),

    .AXI_AWBURST_INCR                   (AXI_AWBURST_INCR          ),
    .AXI_AWLOCK_NORMAL                  (AXI_AWLOCK_NORMAL         ),
    .AXI_AWCACHE_DEVICE_NON_BUF         (AXI_AWCACHE_DEVICE_NON_BUF),
    .AXI_AWPROT_UNPRIV_SECURE           (AXI_AWPROT_UNPRIV_SECURE  ),
    .AXI_AWQOS_DEFAULT                  (AXI_AWQOS_DEFAULT         ),
    .AXI_AWREGION_DEFAULT               (AXI_AWREGION_DEFAULT      ),
    .AXI_BRESP_OKAY                     (AXI_BRESP_OKAY            ),
    .AXI_WSTRB_ALL_VALID                (AXI_WSTRB_ALL_VALID       ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY        ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              )   
) fifo_to_axi4_inst(
  //时钟及复位
    .clk                                (ui_clk                    ),
    .reset                              (reset                     ),

    //FIFO
    .fifo_rdreq                         (rd_en_inst                ),
    .fifo_rddata                        (dout_inst                 ),
    .fifo_empty                         (empty_inst                ),  
    .fifo_rd_cnt                        (rd_data_count_inst        ),
    .fifo_rst_busy                      (rd_rst_busy_inst0         ),

    // Slave 写地址通道
    .m_axi_awid                         (m_axi_awid                ),
    .m_axi_awaddr                       (m_axi_awaddr              ),
    .m_axi_awlen                        (m_axi_awlen               ),
    .m_axi_awsize                       (m_axi_awsize              ),
    .m_axi_awburst                      (m_axi_awburst             ),
    .m_axi_awlock                       (m_axi_awlock              ),
    .m_axi_awcache                      (m_axi_awcache             ),
    .m_axi_awprot                       (m_axi_awprot              ),
    .m_axi_awqos                        (m_axi_awqos               ),
    .m_axi_awregion                     (m_axi_awregion            ),
    .m_axi_awvalid                      (m_axi_awvalid             ),
    .m_axi_awready                      (m_axi_awready             ),

    // Slave 写数据通道
    .m_axi_wdata                        (m_axi_wdata               ),
    .m_axi_wstrb                        (m_axi_wstrb               ),
    .m_axi_wlast                        (m_axi_wlast               ),
    .m_axi_wvalid                       (m_axi_wvalid              ),
    .m_axi_wready                       (m_axi_wready              ),

    // Slave 写响应通道
    .m_axi_bid                          (m_axi_bid                 ),
    .m_axi_bresp                        (m_axi_bresp               ),
    .m_axi_bvalid                       (m_axi_bvalid              ),
    .m_axi_bready                       (m_axi_bready              ),

// ==================== 对外输出的一帧写完信号 ====================
    .camera_w_done                      (camera_w_done             ) // (output)// 帧写完成脉冲
);

//////////////////////////////////////////    axi4接口转fifo接口      //////////////////////////////////////////
  axi4_to_fifo
  #(

    .BUF_A_BEGIN                        (BUF_A_BEGIN               ),
    // .BUF_B_BEGIN                        (BUF_B_BEGIN               ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH            ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH            ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH              ),
    .AXI_ID                             (CAMERA_AXI_ID             ),//每个master的ID不同，需要差异化
    .AXI_BURST_LEN                      (AXI_BURST_LEN             ),
    .FIFO_ADDR_WIDTH                    (FIFO_ADDR_WIDTH           ),

    .AXI_ARBURST_INCR                   (AXI_ARBURST_INCR          ),
    .AXI_ARLOCK_NORMAL                  (AXI_ARLOCK_NORMAL         ),
    .AXI_ARCACHE_DEVICE_NON_BUF         (AXI_ARCACHE_DEVICE_NON_BUF),
    .AXI_ARPROT_UNPRIV_SECURE           (AXI_ARPROT_UNPRIV_SECURE  ),
    .AXI_ARQOS_DEFAULT                  (AXI_ARQOS_DEFAULT         ),
    .AXI_ARREGION_DEFAULT               (AXI_ARREGION_DEFAULT      ),
    .AXI_RRESP_OKAY                     (AXI_RRESP_OKAY            ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY        ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ) 

  )axi4_to_fifo_inst
  (
    //时钟及复位
    .clk                                (ui_clk                         ),
    .reset                              (reset                     ),

    //FIFO
    .fifo_wrreq                         (wr_en_inst                ),
    .fifo_wrdata                        (din_inst                  ),
    .fifo_alfull                        (full_inst                 ),
    .fifo_wr_cnt                        (wr_data_count_inst        ),
    .fifo_rst_busy                      (wr_rst_busy_inst1          ),
  
    

    // Slave 读地址通道
    .m_axi_arid                         (m_axi_arid                ),
    .m_axi_araddr                       (m_axi_araddr              ),
    .m_axi_arlen                        (m_axi_arlen               ),
    .m_axi_arsize                       (m_axi_arsize              ),
    .m_axi_arburst                      (m_axi_arburst             ),
    .m_axi_arlock                       (m_axi_arlock              ),
    .m_axi_arcache                      (m_axi_arcache             ),
    .m_axi_arprot                       (m_axi_arprot              ),
    .m_axi_arqos                        (m_axi_arqos               ),
    .m_axi_arregion                     (m_axi_arregion            ),
    .m_axi_arvalid                      (m_axi_arvalid             ),
    .m_axi_arready                      (m_axi_arready             ),

    // Slave 读数据通道
    .m_axi_rid                          (m_axi_rid                 ),
    .m_axi_rdata                        (m_axi_rdata               ),
    .m_axi_rresp                        (m_axi_rresp               ),
    .m_axi_rlast                        (m_axi_rlast               ),
    .m_axi_rvalid                       (m_axi_rvalid              ),
    .m_axi_rready                       (m_axi_rready              ),

    //实验接口
    // .r_done                             (r_done                    ),//output(用于缓存切换)
    .rd_enable                          (camera_w_done            )
  );


endmodule
