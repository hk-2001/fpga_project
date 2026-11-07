`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/13 10:12:22
// Design Name: HUKUAN
// Module Name: ddr3_ctrl_2port
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

module ddr3_ctrl_2port#(
   
    parameter                           FIFO_DW                     = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit
    parameter                           FIFO_ADDR_WIDTH             = 8,
    // ==================== 地址与数据参数 ====================

    parameter                           BUF_A_BEGIN                 = 32'h0100_0000        ,//缓存A基地址
    parameter                           BUF_B_BEGIN                 = 32'h0120_0000        ,//缓存B基地址（双缓冲）
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
    // ==================== 全局信号 ====================
    input                               ddr3_clk200m               ,
    input                               ddr3_rst                   ,
    output                              ddr3_init_done             ,//当DDR3初始化完成，并且mmcm locked也完成初始化时，才置1
  // ==================== 写FIFO用户写入侧接口 ====================
    input                               wr_clk                     ,
    input  wire          [  15: 0]      din                        ,
    input  wire                         wr_en                      ,
    input wire                          wrfifo_rst                 ,
    output wire                         full                       ,
    output wire          [  10: 0]      wr_data_count              ,
     // ==================== 读FIFO用户侧接口 ====================
    input  wire                         rd_clk                     ,
    input wire                          rdfifo_rst                 ,
    input  wire                         rd_en                      ,
    output wire          [  15: 0]      dout                       ,
    output wire                         empty                      ,
    output wire          [  10: 0]      rd_data_count              ,
     // ==================== DDR3侧接口 ====================
    inout                [  31: 0]      ddr3_dq                    ,
    inout                [   3: 0]      ddr3_dqs_n                 ,
    inout                [   3: 0]      ddr3_dqs_p                 ,

    output               [  14: 0]      ddr3_addr                  ,
    output               [   2: 0]      ddr3_ba                    ,
    output                              ddr3_ras_n                 ,
    output                              ddr3_cas_n                 ,
    output                              ddr3_we_n                  ,
    output                              ddr3_reset_n               ,
    output                              ddr3_ck_p                  ,
    output                              ddr3_ck_n                  ,
    output                              ddr3_cke                   ,
    output                              ddr3_cs_n                  ,
    output               [   3: 0]      ddr3_dm                    ,
    output                              ddr3_odt                   ,
    // ==================== 输出mig侧的时钟和复位 ====================
    output                                ui_clk                   ,  
    output                                ui_clk_sync_rst          ,
       //==================== 实验接口 ====================
    output                               w_done                   
    );
    //参数连接端口
  // ==================== 写地址通道 ====================

    wire                 [AXI_ID_WIDTH-1: 0]m_axi_awid             ;
    wire                 [AXI_ADDR_WIDTH-1: 0]m_axi_awaddr         ;
    wire                 [   7: 0]      m_axi_awlen                ;
    wire                 [   2: 0]      m_axi_awsize               ;
    wire                 [   1: 0]      m_axi_awburst              ;
    wire                 [   0: 0]      m_axi_awlock               ;
    wire                 [   3: 0]      m_axi_awcache              ;
    wire                 [   2: 0]      m_axi_awprot               ;
    wire                 [   3: 0]      m_axi_awqos                ;
    wire                 [   3: 0]      m_axi_awregion             ;
    wire                                m_axi_awvalid              ;
    wire                                m_axi_awready              ;
 // ==================== 写数据通道 ====================

    wire                 [AXI_DATA_WIDTH-1: 0]m_axi_wdata          ;
    wire                 [AXI_DATA_WIDTH/8-1: 0]m_axi_wstrb        ;
    wire                                m_axi_wlast                ;
    wire                                m_axi_wvalid               ;
    wire                                m_axi_wready               ;
 // ==================== 写响应通道 ====================    

    wire                 [AXI_ID_WIDTH-1: 0]m_axi_bid              ;
    wire                 [   1: 0]      m_axi_bresp                ;
    wire                                m_axi_bvalid               ;
    wire                                m_axi_bready               ;
  // ==================== 读地址通道 ====================    

    wire                 [AXI_ID_WIDTH-1: 0]m_axi_arid             ;
    wire                 [AXI_ADDR_WIDTH-1: 0]m_axi_araddr         ;



    wire                 [   7: 0]      m_axi_arlen                ;
    wire                 [   2: 0]      m_axi_arsize               ;
    wire                 [   1: 0]      m_axi_arburst              ;
    wire                 [   0: 0]      m_axi_arlock               ;
    wire                 [   3: 0]      m_axi_arcache              ;
    wire                 [   2: 0]      m_axi_arprot               ;
    wire                 [   3: 0]      m_axi_arqos                ;
    wire                 [   3: 0]      m_axi_arregion             ;
    wire                                m_axi_arvalid              ;
    wire                                m_axi_arready              ;
     // ==================== 读数据通道 ====================   

    wire                 [AXI_ID_WIDTH-1: 0]m_axi_rid              ;
    wire                 [AXI_DATA_WIDTH-1: 0]m_axi_rdata          ;
    wire                 [   1: 0]      m_axi_rresp                ;
    wire                                m_axi_rlast                ;
    wire                                m_axi_rvalid               ;
    wire                                m_axi_rready               ;
      // ==================== 应用层接口 ====================   


    wire                                mmcm_locked                ;
    wire                                init_calib_complete        ;

  assign ddr3_init_done = mmcm_locked && init_calib_complete;

    // UI 去复位：由 init_calib_complete 在 ui_clk 域打一拍给出
    reg                                 aresetn_s                              ;
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst)
            aresetn_s                  <= 1'b0                                 ;
        else
            aresetn_s                  <= init_calib_complete                  ;
    end
//////////////////////////////////////////    fifo与axi4互转       //////////////////////////////////////////

fifo_axi4_adapter#(
    .FIFO_DW                            (FIFO_DW                     ),
    .FIFO_ADDR_WIDTH                    (FIFO_ADDR_WIDTH             ), 
    .BUF_A_BEGIN                        (BUF_A_BEGIN                 ),
    .BUF_B_BEGIN                        (BUF_B_BEGIN                 ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH              ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH              ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH                ),
    .CAMERA_AXI_ID                      (CAMERA_AXI_ID               ),
    .AXI_BURST_LEN                      (AXI_BURST_LEN               ),
    .AXI_ARBURST_INCR                   (AXI_ARBURST_INCR            ),
    .AXI_ARLOCK_NORMAL                  (AXI_ARLOCK_NORMAL           ),
    .AXI_ARCACHE_DEVICE_NON_BUF         (AXI_ARCACHE_DEVICE_NON_BUF  ),
    .AXI_ARPROT_UNPRIV_SECURE           (AXI_ARPROT_UNPRIV_SECURE    ),
    .AXI_ARQOS_DEFAULT                  (AXI_ARQOS_DEFAULT           ),
    .AXI_ARREGION_DEFAULT               (AXI_ARREGION_DEFAULT        ),
    .AXI_RRESP_OKAY                     (AXI_RRESP_OKAY              ),
    .AXI_AWBURST_INCR                   (AXI_AWBURST_INCR            ),
    .AXI_AWLOCK_NORMAL                  (AXI_AWLOCK_NORMAL           ),
    .AXI_AWCACHE_DEVICE_NON_BUF         (AXI_AWCACHE_DEVICE_NON_BUF  ),
    .AXI_AWPROT_UNPRIV_SECURE           (AXI_AWPROT_UNPRIV_SECURE    ),
    .AXI_AWQOS_DEFAULT                  (AXI_AWQOS_DEFAULT           ),
    .AXI_AWREGION_DEFAULT               (AXI_AWREGION_DEFAULT        ),
    .AXI_BRESP_OKAY                     (AXI_BRESP_OKAY              ),
    .AXI_WSTRB_ALL_VALID                (AXI_WSTRB_ALL_VALID         ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY          ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH                 ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT                ) 
)
 u_fifo_axi4_adapter(
    .ui_clk                             (ui_clk                    ),
    .reset                              (ui_clk_sync_rst           ),
//写FIFO侧接口
    .wr_clk                             (wr_clk                    ),// input
    .din                                (din                       ),// input  wire [15:0]
    .wr_en                              (wr_en                     ),// input  wire
    .wrfifo_rst                         (wrfifo_rst                ),// input  wire
    .full                               (full                      ),// output wire
    .wr_data_count                      (wr_data_count             ), // output wire [10:0]
//读FIFO侧接口
    .rd_clk                             (rd_clk                    ),// input  wire
    .rdfifo_rst                         (rdfifo_rst                ),// input  wire
    .rd_en                              (rd_en                     ),// input  wire
    .dout                               (dout                      ),// output wire [15:0]
    .empty                              (empty                     ),// output wire
    .rd_data_count                      (rd_data_count             ), // output wire [12:0]
//写地址通道
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
//写数据通道
    .m_axi_wdata                        (m_axi_wdata               ),
    .m_axi_wstrb                        (m_axi_wstrb               ),
    .m_axi_wlast                        (m_axi_wlast               ),
    .m_axi_wvalid                       (m_axi_wvalid              ),
    .m_axi_wready                       (m_axi_wready              ),
//写响应通道
    .m_axi_bid                          (m_axi_bid                 ),
    .m_axi_bresp                        (m_axi_bresp               ),
    .m_axi_bvalid                       (m_axi_bvalid              ),
    .m_axi_bready                       (m_axi_bready              ),
//读地址通道
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
//读数据通道
    .m_axi_rid                          (m_axi_rid                 ),
    .m_axi_rdata                        (m_axi_rdata               ),
    .m_axi_rresp                        (m_axi_rresp               ),
    .m_axi_rlast                        (m_axi_rlast               ),
    .m_axi_rvalid                       (m_axi_rvalid              ),
    .m_axi_rready                       (m_axi_rready              ),
//实验接口
    .camera_w_done                      (w_done                    )
);


//////////////////////////////////////////    MIG控制器       //////////////////////////////////////////


mig_7series_0 mig_7series_0_inst(

    // DDR3接口
    .ddr3_addr                          (ddr3_addr                 ),// output [14:0]		ddr3_addr
    .ddr3_ba                            (ddr3_ba                   ),// output [2:0]		ddr3_ba
    .ddr3_cas_n                         (ddr3_cas_n                ),// output			    ddr3_cas_n
    .ddr3_ck_n                          (ddr3_ck_n                 ),// output [0:0]		ddr3_ck_n
    .ddr3_ck_p                          (ddr3_ck_p                 ),// output [0:0]		ddr3_ck_p
    .ddr3_cke                           (ddr3_cke                  ),// output [0:0]		ddr3_cke
    .ddr3_ras_n                         (ddr3_ras_n                ),// output			    ddr3_ras_n
    .ddr3_reset_n                       (ddr3_reset_n              ),// output			    ddr3_reset_n
    .ddr3_we_n                          (ddr3_we_n                 ),// output			    ddr3_we_n
    .ddr3_dq                            (ddr3_dq                   ),// inout [31:0]		ddr3_dq
    .ddr3_dqs_n                         (ddr3_dqs_n                ),// inout [3:0]		    ddr3_dqs_n
    .ddr3_dqs_p                         (ddr3_dqs_p                ),// inout [3:0]		    ddr3_dqs_p
    .init_calib_complete                (init_calib_complete       ),// output			    init_calib_complete
    .ddr3_cs_n                          (ddr3_cs_n                 ),// output [0:0]		ddr3_cs_n
    .ddr3_dm                            (ddr3_dm                   ),// output [3:0]		ddr3_dm
    .ddr3_odt                           (ddr3_odt                  ),// output [0:0]		ddr3_odt

    //应用层接口

    .ui_clk                             (ui_clk                    ),// output			    ui_clk
    .ui_clk_sync_rst                    (ui_clk_sync_rst           ),// output			    ui_clk_sync_rst
    .mmcm_locked                        (mmcm_locked               ),// output			    mmcm_locked
    .aresetn                            (aresetn_s                             ),// input			    aresetn
   
 //信号
// app_sr_req
// Self-Refresh Request
// 请求 DDR 进入自刷新模式（低功耗休眠）
// app_ref_req
// Refresh Request
// 请求 DDR 执行手动刷新（正常情况下 MIG 自动刷新）
// app_zq_req
// ZQ Calibration Request
// 请求 DDR 执行 ZQ 校准（校准输出驱动阻抗）
// app_sr_active
// Self-Refresh Active
// 指示当前 DDR 是否处于自刷新状态
// app_ref_ack
// Refresh Acknowledge
// 手动刷新的应答
// app_zq_ack
// ZQ Calibration Acknowledge
// ZQ 校准完成的应答

    .app_sr_req                         (0                         ),// input			    app_sr_req
    .app_ref_req                        (0                         ),// input			    app_ref_req
    .app_zq_req                         (0                         ),// input			    app_zq_req
    .app_sr_active                      (                          ),// output			    app_sr_active
    .app_ref_ack                        (                          ),// output			    app_ref_ack
    .app_zq_ack                         (                          ),// output			    app_zq_ack

    // Slave 写地址通道
    .s_axi_awid                         (m_axi_awid                ),// input [3:0]			s_axi_awid
    .s_axi_awaddr                       (m_axi_awaddr              ),// input [29:0]			s_axi_awaddr
    .s_axi_awlen                        (m_axi_awlen               ),// input [7:0]			s_axi_awlen
    .s_axi_awsize                       (m_axi_awsize              ),// input [2:0]			s_axi_awsize
    .s_axi_awburst                      (m_axi_awburst             ),// input [1:0]			s_axi_awburst
    .s_axi_awlock                       (m_axi_awlock              ),// input [0:0]			s_axi_awlock
    .s_axi_awcache                      (m_axi_awcache             ),// input [3:0]			s_axi_awcache
    .s_axi_awprot                       (m_axi_awprot              ),// input [2:0]			s_axi_awprot
    .s_axi_awqos                        (m_axi_awqos               ),// input [3:0]			s_axi_awqos
    .s_axi_awvalid                      (m_axi_awvalid             ),// input			    s_axi_awvalid
    .s_axi_awready                      (m_axi_awready             ),// output			    s_axi_awready
    // Slave 写数据通道
    .s_axi_wdata                        (m_axi_wdata               ),// input [127:0]	    s_axi_wdata
    .s_axi_wstrb                        (m_axi_wstrb               ),// input [15:0]	    s_axi_wstrb
    .s_axi_wlast                        (m_axi_wlast               ),// input			    s_axi_wlast
    .s_axi_wvalid                       (m_axi_wvalid              ),// input			    s_axi_wvalid
    .s_axi_wready                       (m_axi_wready              ),// output			    s_axi_wready
    // Slave 写响应通道
    .s_axi_bid                          (m_axi_bid                 ),// output [3:0]		s_axi_bid
    .s_axi_bresp                        (m_axi_bresp               ),// output [1:0]		s_axi_bresp
    .s_axi_bvalid                       (m_axi_bvalid              ),// output			    s_axi_bvalid
    .s_axi_bready                       (m_axi_bready              ),// input			    s_axi_bready
    // Slave 读地址通道
    .s_axi_arid                         (m_axi_arid                ),// input [3:0]			s_axi_arid
    .s_axi_araddr                       (m_axi_araddr              ),// input [29:0]		s_axi_araddr
    .s_axi_arlen                        (m_axi_arlen               ),// input [7:0]			s_axi_arlen
    .s_axi_arsize                       (m_axi_arsize              ),// input [2:0]			s_axi_arsize
    .s_axi_arburst                      (m_axi_arburst             ),// input [1:0]			s_axi_arburst
    .s_axi_arlock                       (m_axi_arlock              ),// input [0:0]			s_axi_arlock
    .s_axi_arcache                      (m_axi_arcache             ),// input [3:0]			s_axi_arcache
    .s_axi_arprot                       (m_axi_arprot              ),// input [2:0]			s_axi_arprot
    .s_axi_arqos                        (m_axi_arqos               ),// input [3:0]			s_axi_arqos
    .s_axi_arvalid                      (m_axi_arvalid             ),// input			    s_axi_arvalid
    .s_axi_arready                      (m_axi_arready             ),// output			    s_axi_arready
    // Slave 读数据通道
    .s_axi_rid                          (m_axi_rid                 ),// output [3:0]		s_axi_rid
    .s_axi_rdata                        (m_axi_rdata               ),// output [127:0]		s_axi_rdata
    .s_axi_rresp                        (m_axi_rresp               ),// output [1:0]		s_axi_rresp
    .s_axi_rlast                        (m_axi_rlast               ),// output			    s_axi_rlast
    .s_axi_rvalid                       (m_axi_rvalid              ),// output			    s_axi_rvalid
    .s_axi_rready                       (m_axi_rready              ),// input			    s_axi_rready
    // System Clock Ports
    .sys_clk_i                          (ddr3_clk200m              ),
    .sys_rst                            (ddr3_rst                  ) // input               sys_rst
    );
endmodule
