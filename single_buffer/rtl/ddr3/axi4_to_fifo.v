`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Module Name : axi4_to_fifo
// Create Date : 2026/09/13 10:45:59
// Description : 单缓冲 AXI4 读主机至 FIFO 写接口适配器。
//               启动后循环读取 A 缓冲区，按突发次数统计帧完成。
// 说明        : 
// 时钟约束    : FIFO 写侧及控制信号应与 clk 同域，或由外部完成跨域处理。
// 启动约束    : rd_enable 生效前，外部必须保证 A 区已有完整有效帧。
//////////////////////////////////////////////////////////////////////////////////

module axi4_to_fifo #(
    // 地址与数据配置；地址单位为字节。
    parameter BUF_A_BEGIN                = 32'h0100_0000,
    parameter AXI_DATA_WIDTH             = 128,
    parameter AXI_ADDR_WIDTH             = 32,
    parameter AXI_ID_WIDTH               = 4,
    parameter AXI_ID                     = 0,
    parameter AXI_BURST_LEN              = 31, // ARLEN：实际突发拍数减一
    parameter FIFO_ADDR_WIDTH            = 8,  // 写侧计数位宽，容量按 2**此值估算

    // AXI 固定属性。
    parameter AXI_ARBURST_INCR           = 2'b01,
    parameter AXI_ARLOCK_NORMAL          = 1'b0,
    parameter AXI_ARCACHE_DEVICE_NON_BUF = 4'b0000,
    parameter AXI_ARPROT_UNPRIV_SECURE   = 3'b000,
    parameter AXI_ARQOS_DEFAULT          = 4'b0000,
    parameter AXI_ARREGION_DEFAULT       = 4'b0000,
    parameter AXI_RRESP_OKAY             = 2'b00,
    parameter AXI_RESET_POLARITY         = 1'b1, // 未使用，逻辑固定高 低有效异步复位
    parameter AXI_RESP_OKAY              = 2'b00,

    // 图像大小；当前公式固定每像素 2 字节。
    parameter IMAGE_WIDTH                = 1280,
    parameter IMAGE_HEIGHT               = 720
) (
    // 全局时钟与高有效异步复位。
    input                                clk,
    input                                reset,

    // FIFO 写接口：写使能与数据同时寄存一拍输出。
    output reg                           fifo_wrreq,
    output reg [AXI_DATA_WIDTH-1:0]       fifo_wrdata,
    input                                fifo_alfull,   // 几乎满标志，高有效
    input [FIFO_ADDR_WIDTH-1:0]          fifo_wr_cnt,   // FIFO 写侧数据字计数
    input                                fifo_rst_busy, // FIFO 复位忙，高有效

    // AXI 读地址通道：ARVALID 与 ARREADY 同时为高时握手。
    output [AXI_ID_WIDTH-1:0]            m_axi_arid,
    output reg [AXI_ADDR_WIDTH-1:0]      m_axi_araddr,
    output [7:0]                         m_axi_arlen,
    output [2:0]                         m_axi_arsize,
    output [1:0]                         m_axi_arburst,
    output [0:0]                         m_axi_arlock,
    output [3:0]                         m_axi_arcache,
    output [2:0]                         m_axi_arprot,
    output [3:0]                         m_axi_arqos,
    output [3:0]                         m_axi_arregion,
    output reg                           m_axi_arvalid,
    input                                m_axi_arready,

    // AXI 读数据通道：RVALID 与 RREADY 同时为高时接收一拍。
    input [AXI_ID_WIDTH-1:0]             m_axi_rid,
    input [AXI_DATA_WIDTH-1:0]           m_axi_rdata,
    input [1:0]                          m_axi_rresp,
    input                                m_axi_rlast,
    input                                m_axi_rvalid,
    output                               m_axi_rready,

    // r_done：AXI 帧接收完成，不是 FIFO 最后一拍写入完成。
    // rd_enable：首次启动后锁存有效，拉低不会停止读取。
    // output                               r_done,
    input                                rd_enable
);

    //==========================================================================
    // 状态与长度参数
    // 单个未完成突发：空闲 -> 地址握手 -> 数据接收 -> 空闲。
    //==========================================================================
    reg [2:0] current_state;
    reg [2:0] next_state;
    localparam S_IDLE    = 3'b001,
               S_RD_ADDR = 3'b010,
               S_RD_RESP = 3'b100;

    wire [FIFO_ADDR_WIDTH-1:0] rd_req_cnt_thresh;

    localparam DATA_SIZE           = $clog2(AXI_DATA_WIDTH/8);
    localparam BURST_BYTE_LEN      = (AXI_BURST_LEN + 1) * (AXI_DATA_WIDTH/8);
    localparam FIFO_SAFE_THRESHOLD = 2**FIFO_ADDR_WIDTH - (AXI_BURST_LEN[7:0]+1'b1);
    localparam BURST_COUNT         = IMAGE_WIDTH*IMAGE_HEIGHT*2/((AXI_BURST_LEN[7:0]+1'b1)*(AXI_DATA_WIDTH/8));
    localparam TOTAL_BEATS         = (IMAGE_WIDTH*IMAGE_HEIGHT*2/(AXI_DATA_WIDTH/8));
    // 默认每突发 512 字节、每帧 3600 个突发。TOTAL_BEATS 当前未使用。
    // 参数应保证帧长整除突发长度，并保证计数器宽度与 FIFO 阈值合法。

    //==========================================================================
    // 固定 AXI 地址属性
    //==========================================================================
    assign m_axi_arsize   = DATA_SIZE;
    assign m_axi_arid     = AXI_ID;
    assign m_axi_arburst  = AXI_ARBURST_INCR;
    assign m_axi_arlock   = AXI_ARLOCK_NORMAL;
    assign m_axi_arcache  = AXI_ARCACHE_DEVICE_NON_BUF;
    assign m_axi_arprot   = AXI_ARPROT_UNPRIV_SECURE;
    assign m_axi_arqos    = AXI_ARQOS_DEFAULT;
    assign m_axi_arregion = AXI_ARREGION_DEFAULT;
    assign m_axi_arlen    = AXI_BURST_LEN;

    // 状态寄存器。
    always @(posedge clk or posedge reset) begin
        if (reset)
            current_state <= S_IDLE;
        else
            current_state <= next_state;
    end

    reg rd_ddr3_req_pulse;

    // 次态逻辑。原来逻辑仅在正常响应末拍握手后退出数据态；
    // 错误末拍的收尾和恢复未实现，按原样保留。
    always @(*) begin
        if (reset)
            next_state = S_IDLE;
        else
            case (current_state)
                S_IDLE: begin
                    if (rd_ddr3_req_pulse)
                        next_state = S_RD_ADDR;
                    else
                        next_state = S_IDLE;
                end
                S_RD_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready)
                        next_state = S_RD_RESP;
                    else
                        next_state = S_RD_ADDR;
                end
                S_RD_RESP: begin
                    if (m_axi_rvalid && m_axi_rready && m_axi_rlast &&
                        (m_axi_rresp == AXI_RESP_OKAY) &&
                        (m_axi_rid == AXI_ID))
                        next_state = S_IDLE;
                    else
                        next_state = S_RD_RESP;
                end
                default: next_state = S_IDLE;
            endcase
    end

    //==========================================================================
    // 数据接收保护与启动控制
    // busy 阻止新握手，但不能撤回上一拍已经寄存的 FIFO 待写数据。
    //==========================================================================
    assign m_axi_rready = (~fifo_alfull) && (reset == 0) &&
                          (fifo_rst_busy == 0) && (current_state == S_RD_RESP);

    reg frame_active;

    always @(posedge clk or posedge reset) begin
        if (reset)
            frame_active <= 0;
        else if (rd_enable)
            frame_active <= 1;
    end

    // 默认阈值为 224，比较条件为 fifo_wr_cnt < 222。
    // 221 是允许启动新突发时的最大计数，不是 FIFO 最大占用量。
    // 已启动的突发允许继续接收，直到 RREADY 背压或突发结束。
    assign rd_req_cnt_thresh = FIFO_SAFE_THRESHOLD[FIFO_ADDR_WIDTH-1:0];
    wire rd_ddr3_condition;
    assign rd_ddr3_condition = (fifo_wr_cnt < rd_req_cnt_thresh - 2) &&
                              ~fifo_rst_busy && frame_active;

    // 寄存请求。名称虽含 pulse，但条件持续满足时结合当前状态机
    // 通常会保持两周期，并不保证单周期脉冲。
    always @(posedge clk or posedge reset) begin
        if (reset)
            rd_ddr3_req_pulse <= 0;
        else if (rd_ddr3_condition && current_state == S_IDLE)
            rd_ddr3_req_pulse <= 1;
        else
            rd_ddr3_req_pulse <= 0;
    end

    //==========================================================================
    // 帧内突发计数与完成脉冲
    // 仅依据握手、RLAST、RID 和 frame_active 计数，原逻辑未检查 RRESP。
    // 因此错误响应时计数与状态退出的处理条件不同，未在此修复。
    //==========================================================================
    reg [($clog2(BURST_COUNT)-1):0] rd_burst_done_cnt;
    reg r_brust_complete;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rd_burst_done_cnt <= 0;
            r_brust_complete <= 0;
        end
        else if (m_axi_rvalid && m_axi_rready && m_axi_rlast &&
                 (m_axi_rid == AXI_ID) && frame_active) begin
            if (rd_burst_done_cnt == BURST_COUNT-1) begin
                r_brust_complete <= 1;
                rd_burst_done_cnt <= 0;
            end
            else begin
                rd_burst_done_cnt <= rd_burst_done_cnt + 1;
                r_brust_complete <= 0;
            end
        end
        else
            r_brust_complete <= 0;
    end

    // assign r_done = r_brust_complete;

    //==========================================================================
    // 读地址产生
    // 复位从 A 开始；每个正常突发结束增加 BURST_BYTE_LEN。
    // T0 为帧末接收沿时，完成寄存器随后置位，T1 回装 A 基地址。
    // 当前单缓冲模式不负责防止外部写端覆盖正在读取的帧。
    //==========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset)
            m_axi_araddr <= BUF_A_BEGIN;
        else if (r_brust_complete)
            m_axi_araddr <= BUF_A_BEGIN;
        else if ((current_state == S_RD_RESP) &&
                 m_axi_rready && m_axi_rvalid && m_axi_rlast &&
                 (m_axi_rresp == AXI_RRESP_OKAY) &&
                 (m_axi_rid == AXI_ID) && frame_active)
            m_axi_araddr <= m_axi_araddr + BURST_BYTE_LEN;
        else
            m_axi_araddr <= m_axi_araddr;
    end

    // 地址有效保持至 AR 握手，不是固定单周期脉冲。
    always @(posedge clk or posedge reset) begin
        if (reset)
            m_axi_arvalid <= 0;
        else if ((current_state == S_RD_ADDR) && m_axi_arready && m_axi_arvalid)
            m_axi_arvalid <= 0;
        else if ((current_state == S_RD_ADDR))
            m_axi_arvalid <= 1;
        else
            m_axi_arvalid <= m_axi_arvalid;
    end

    //==========================================================================
    // FIFO 写端寄存输出
    // AXI 在本沿接收的数据，在相同 clk 的 FIFO 下一个沿写入。
    // 当前写入条件不额外检查 RID/RRESP，错误帧策略由后续设计明确。
    //==========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset)
            fifo_wrreq <= 1'b0;
        else
            fifo_wrreq <= m_axi_rvalid & m_axi_rready && frame_active;
    end

    // 数据寄存器无复位：首次有效接收之前仿真可能为 X。
    // fifo_wrreq=0 时数据无效；只有实际写入时的数据才需计入验证。
    always @(posedge clk) begin
        if (m_axi_rvalid && m_axi_rready && frame_active)
            fifo_wrdata <= m_axi_rdata;
    end

endmodule



