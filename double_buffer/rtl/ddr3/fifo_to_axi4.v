// =============================================================================
// Design Name : HUKUAN
// Module Name : fifo_to_axi4
// 设计说明    : 同步 FIFO 至 AXI4 写通道的单事务帧写入控制器
// =============================================================================
// =============================================================================
`timescale 1ns / 1ps
module fifo_to_axi4
#(

// -------------------------------------------------------------------------
// 01 参数定义
// BUF_A_BEGIN 为固定帧缓冲基址；当前每帧完成后回绕到该地址。
    // -------------------------------------------------------------------------
    parameter BUF_A_BEGIN = 32'h0100_0000,
    parameter BUF_B_BEGIN = 32'h0120_0000,   // 双缓冲：B 缓冲基址（A 之后 2MB）

    // -------------------------------------------------------------------------
    // 数据、地址和事务 ID 位宽；FIFO 数据宽度与 AXI 写数据宽度一致。
    // -------------------------------------------------------------------------
    parameter AXI_DATA_WIDTH = 128,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_ID_WIDTH = 4,
    parameter AXI_ID = 4'b0000,

    // -------------------------------------------------------------------------
    // AWLEN 编码：每次发送 AXI_BURST_LEN + 1 拍，默认 32 拍。
    // -------------------------------------------------------------------------
    parameter AXI_BURST_LEN = 8'd31,

    // -------------------------------------------------------------------------
    // FIFO 已有数据字数的计数端口位宽，不代表 AXI 地址位宽。
    // -------------------------------------------------------------------------
    parameter FIFO_ADDR_WIDTH = 8,

    // -------------------------------------------------------------------------
    // AXI 属性参数：默认 INCR、普通访问、非缓存非缓冲设备属性。
    // PROT 默认非特权/安全/数据访问，QOS 与 REGION 默认零，成功响应为 OKAY。
    // -------------------------------------------------------------------------
    parameter AXI_AWBURST_INCR = 2'b01,
    parameter AXI_AWLOCK_NORMAL = 1'b0,
    parameter AXI_AWCACHE_DEVICE_NON_BUF = 4'b0000,
    parameter AXI_AWPROT_UNPRIV_SECURE = 3'b000,
    parameter AXI_AWQOS_DEFAULT = 4'b0000,
    parameter AXI_AWREGION_DEFAULT = 4'b0000,
    parameter AXI_BRESP_OKAY = 2'b00,

    // -------------------------------------------------------------------------
    // 按参数本身的实际位宽复制后赋给 WSTRB；默认 1 位的 1 选通所有字节。
    // -------------------------------------------------------------------------
    parameter AXI_WSTRB_ALL_VALID = 1'b1,

    // -------------------------------------------------------------------------
    // 保留的未使用参数；实际 reset 始终异步高有效。
    // -------------------------------------------------------------------------
    parameter AXI_RESET_POLARITY = 1'b1,

    // -------------------------------------------------------------------------
    // 图像宽高按像素计；帧大小固定使用每像素 2 字节的假设。
    // -------------------------------------------------------------------------
    parameter IMAGE_WIDTH = 1280,
    parameter IMAGE_HEIGHT = 720
)
(

    // -------------------------------------------------------------------------
    // 02 端口定义 / 时钟与复位
    // FIFO 读接口和 AXI 控制均按 clk 采样，无内部跨时钟域处理。
    // -------------------------------------------------------------------------
    input clk,
    input reset,

    // -------------------------------------------------------------------------
    // FIFO 读接口：rdreq 为寄存器读脉冲，rddata 为同步读返回数据。
    // empty、rd_cnt、rst_busy 共同控制事务启动；启动后不逐拍重新检查 empty。
    // -------------------------------------------------------------------------
    output reg fifo_rdreq,
    input [AXI_DATA_WIDTH-1:0] fifo_rddata,
    input fifo_empty,
    input [FIFO_ADDR_WIDTH-1:0] fifo_rd_cnt,
    input fifo_rst_busy,

    // -------------------------------------------------------------------------
    // AXI 写地址通道：AWVALID 保持到握手；AWLEN 为拍数减一，AWSIZE 为字节数对数。
    // AWID 与其余属性来自参数，AWADDR 在成功响应后推进或在帧完成后回绕。
    // -------------------------------------------------------------------------
    output [AXI_ID_WIDTH-1:0] m_axi_awid,
    (* mark_debug = "true" *) output reg [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,   // [ILA] 双缓存验证：应在 A/B 基址间交替
    output [7:0] m_axi_awlen,
    output [2:0] m_axi_awsize,
    output [1:0] m_axi_awburst,
    output [0:0] m_axi_awlock,
    output [3:0] m_axi_awcache,
    output [2:0] m_axi_awprot,
    output [3:0] m_axi_awqos,
    output [3:0] m_axi_awregion,
    output reg m_axi_awvalid,
    input m_axi_awready,

    // -------------------------------------------------------------------------
    // AXI 写数据通道：WDATA 来自单级保持寄存器；WVALID/WREADY 同时为高才消费。
    // WSTRB 每一位对应一个字节；WLAST 标识当前突发末拍，并随背压保持。
    // -------------------------------------------------------------------------
    output [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg m_axi_wlast,
    output reg m_axi_wvalid,
    input m_axi_wready,

    // -------------------------------------------------------------------------
    // AXI 写响应通道：仅 BID 匹配且 BRESP 成功才推进正常完成流程。
    // -------------------------------------------------------------------------
    input [AXI_ID_WIDTH-1:0] m_axi_bid,
    input [1:0] m_axi_bresp,
    input m_axi_bvalid,
    output m_axi_bready,

    // -------------------------------------------------------------------------
    // 帧完成输出：直接连接 w_brust_complete，无延迟链；按成功 B 响应数量定义帧边界。
    // -------------------------------------------------------------------------
    output camera_w_done,
    // -------------------------------------------------------------------------
    // 双缓冲接口：写基地址由外部乒乓控制器给出
    // -------------------------------------------------------------------------
    input        [AXI_ADDR_WIDTH-1:0]   wr_base_addr,
    // 缓冲切换脉冲（由乒乓控制器发出）：上升沿装载新的写基址
    input                               w_addr_switch_pulse
);

    // -------------------------------------------------------------------------
    // 03 局部参数 / 字节步进、启动门限与帧计数
    // DATA_SIZE 编码每拍字节数；BURST_BYTE_LEN 同时用于地址步进。
    // WR_REQ_THRESHOLD 要求 FIFO 至少积累一个完整突发。
    // BURST_COUNT 为整数除法结果，保留切片及 1'b1 等所有原有表达式位宽。
    // -------------------------------------------------------------------------
    localparam DATA_SIZE = $clog2(AXI_DATA_WIDTH/8);
    localparam BURST_BYTE_LEN = (AXI_BURST_LEN + 1) * (AXI_DATA_WIDTH/8);
    localparam WR_REQ_THRESHOLD = AXI_BURST_LEN + 1;
    localparam BURST_COUNT = IMAGE_WIDTH*IMAGE_HEIGHT*2/((AXI_BURST_LEN[7:0]+1'b1)*(AXI_DATA_WIDTH/8));

    // -------------------------------------------------------------------------
    // 04 状态编码与内部寄存器
    // 五位独热状态：空闲、地址握手、首拍准备、数据传输、响应等待。
    // -------------------------------------------------------------------------
    reg [4:0] current_state;
    reg [4:0] next_state;
    localparam S_IDLE = 5'b00001,
        S_WR_ADDR = 5'b00010,
        S_WR_DATA_PRE = 5'b00100,
        S_WR_DATA = 5'b01000,
        S_WR_RESP = 5'b10000;

    // -------------------------------------------------------------------------
    // wr_req_cnt_thresh 为门限连线；wr_ddr3_req 为组合启动条件。
    // fifo_rddata_valid 延迟标记读请求；fifo_rddata_latch 提供一拍深度（1-deep）保持。
    // wr_data_cnt 累计本突发 W 握手；w_burst_done_cnt 累计本帧成功 B 响应。
    // w_brust_complete 是帧完成脉冲寄存器，名称保持不变。
    // -------------------------------------------------------------------------
    wire [$clog2((AXI_BURST_LEN + 1) ):0] wr_req_cnt_thresh;
    reg wr_ddr3_req;
    reg fifo_rddata_valid;
    reg [AXI_DATA_WIDTH-1:0] fifo_rddata_latch;
    reg [$clog2((AXI_BURST_LEN + 1) ):0] wr_data_cnt;
    reg [$clog2(BURST_COUNT)-1:0] w_burst_done_cnt;
    reg w_brust_complete;

    // -------------------------------------------------------------------------
    // 05 固定属性与直连输出
    // -------------------------------------------------------------------------
    assign m_axi_awid = AXI_ID;
    assign m_axi_awsize = DATA_SIZE;
    assign m_axi_awburst = AXI_AWBURST_INCR;
    assign m_axi_awlock = AXI_AWLOCK_NORMAL;
    assign m_axi_awcache = AXI_AWCACHE_DEVICE_NON_BUF;
    assign m_axi_awprot = AXI_AWPROT_UNPRIV_SECURE;
    assign m_axi_awqos = AXI_AWQOS_DEFAULT;
    assign m_axi_awregion = AXI_AWREGION_DEFAULT;
    assign m_axi_awlen = AXI_BURST_LEN;
    assign m_axi_wstrb = {(AXI_DATA_WIDTH/8){AXI_WSTRB_ALL_VALID}};
    assign camera_w_done = w_brust_complete;

    // -------------------------------------------------------------------------
    // 06 状态机 / 状态寄存器
    // 复位进入 IDLE；其余周期采样组合 next_state。
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if(reset)
            current_state<=S_IDLE;
        else
            current_state<=next_state;
    end

    // -------------------------------------------------------------------------
    // 状态机 / 组合转移
    // IDLE 等待足量数据；AW 握手后经过 PRE 一拍进入 DATA。
    // DATA 仅在末拍握手后进入 RESP；RESP 等待匹配 ID 的成功响应才回到 IDLE。
    // -------------------------------------------------------------------------
    always @(*) begin
        case (current_state)
            S_IDLE :begin
                if(wr_ddr3_req==1)
                    next_state=S_WR_ADDR;
                else
                    next_state=S_IDLE;
            end
            S_WR_ADDR :begin
                if(m_axi_awready && m_axi_awvalid)
                    next_state = S_WR_DATA_PRE;
                else
                    next_state = S_WR_ADDR;
            end
            S_WR_DATA_PRE :begin
                next_state = S_WR_DATA;
            end
            S_WR_DATA :begin
                if(m_axi_wready && m_axi_wvalid && m_axi_wlast)
                    next_state = S_WR_RESP;

                else
                    next_state = S_WR_DATA;
            end
            S_WR_RESP :begin
                if(m_axi_bready && m_axi_bvalid &&(m_axi_bresp == AXI_BRESP_OKAY)&& (m_axi_bid == AXI_ID))
                    next_state = S_IDLE;
                else
                    next_state = S_WR_RESP;
            end
            default: next_state=S_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // 07 响应接收策略
    // BREADY 恒为 1，不对响应施加背压；握手成功不等于响应状态成功。
    // -------------------------------------------------------------------------
    assign m_axi_bready = 1'b1;

    // -------------------------------------------------------------------------
    // 08 FIFO 启动条件
    // 计数达到一整个突发、非空且复位不忙时允许启动；状态机仅在 IDLE 采用该条件。
    // -------------------------------------------------------------------------
    assign wr_req_cnt_thresh = WR_REQ_THRESHOLD;

    // 组合生成写请求，不锁存；事务推进由状态机控制。
    always @(*) begin
        if((fifo_rd_cnt>=wr_req_cnt_thresh)&&
                (~fifo_empty)&&
                (fifo_rst_busy==0)
                )
            wr_ddr3_req=1;
        else
            wr_ddr3_req=0;
    end

    // -------------------------------------------------------------------------
    // 09 成功响应计数与帧完成脉冲
    // 匹配 ID 的 OKAY B 握手使计数加一；最后一个响应使计数归零并置 done。
    // 此计数条件不受 current_state 限定，依赖系统提供与已发事务相符的响应。
    // 正常单事务流程中 done 高一个周期；无合格响应时清零 done，计数保持。
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if(reset)begin
            w_burst_done_cnt<=0;
            w_brust_complete <=0;
        end
        else if(m_axi_bready && m_axi_bvalid &&(m_axi_bresp == AXI_BRESP_OKAY)&& (m_axi_bid == AXI_ID))begin
            if (w_burst_done_cnt == BURST_COUNT -1) begin
                w_burst_done_cnt<=0;
                w_brust_complete <=1;
            end
            else begin
                w_burst_done_cnt<=w_burst_done_cnt+1;
                w_brust_complete <=0;
            end
        end
        else
            w_brust_complete<=0;
    end

    // -------------------------------------------------------------------------
    // 10 写地址更新 / 直接 done 回绕
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if(reset)
            m_axi_awaddr <= BUF_A_BEGIN;
        else if(w_addr_switch_pulse)
            m_axi_awaddr <= wr_base_addr;      // 缓冲切换脉冲 → 装载新基址，其后按 +512 递增
        else if(m_axi_bvalid&&m_axi_bready&&(m_axi_bresp==AXI_BRESP_OKAY)&&(current_state == S_WR_RESP)&&(m_axi_bid == AXI_ID))
            m_axi_awaddr <= m_axi_awaddr+BURST_BYTE_LEN;
        else
            m_axi_awaddr <= m_axi_awaddr;
    end

    // -------------------------------------------------------------------------
    // 11 AWVALID 保持
    // 进入地址态后寄存器置位，在地址态握手时清零；等待期间保持有效及地址。
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if(reset)
            m_axi_awvalid <= 0;
        else if(((current_state == S_WR_ADDR))&&m_axi_awvalid&&m_axi_awready)
            m_axi_awvalid <= 0;
        else if (current_state == S_WR_ADDR)
            m_axi_awvalid <= 1;
        else
            m_axi_awvalid <= m_axi_awvalid;
    end

    // -------------------------------------------------------------------------
    // 12 同步 FIFO 读请求
    // AW 握手后发首个读脉冲；每次非末拍 W 握手后才请求下一字。
    // -------------------------------------------------------------------------
    always@(posedge clk or posedge reset)begin
        if(reset)
            fifo_rdreq <= 0;
        else if(((current_state == S_WR_ADDR))&&m_axi_awvalid&&m_axi_awready)
            fifo_rdreq <= 1;
        else if(((current_state == S_WR_DATA))&&m_axi_wvalid&&m_axi_wready&&(~m_axi_wlast))
            fifo_rdreq <= 1;
        else
            fifo_rdreq <= 0;
    end

    // -------------------------------------------------------------------------
    // 13 同步读与非阻塞赋值（NBA）时序
    // 以 AW 握手沿 T0 为例：T0 后 fifo_rdreq=1；T1 FIFO 采样请求并在 NBA 更新
    // rddata，同时此处将 fifo_rddata_valid 置 1；T2 保持寄存器读取已经稳定的 rddata，
    // 并置 WVALID，最早 T3 完成 W 握手。若为非末拍，T3 再发读请求，
    // 随后 T4 读出、T5 捕获、T6 握手；理想无背压下也不是每拍传输。
    // 该时序依赖同步 FIFO 的上述延迟，不适用于任意 FIFO 输出模式。
    // 本块没有 reset：复位期间仍随 clk 采样 fifo_rdreq，而不是异步清零。
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        fifo_rddata_valid <= fifo_rdreq;
    end

    // -------------------------------------------------------------------------
    // 14 FIFO 数据保持寄存器
    // 在延迟有效标志到达时捕获 FIFO 输出；同一沿 WVALID 置位，数据和有效同步出现。
    // 未捕获新数据时保持原值，正常协议序列下可承受任意长度的 WREADY 背压。
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if(reset)
            fifo_rddata_latch <= {AXI_DATA_WIDTH{1'b0}};
        else if(fifo_rddata_valid)
            fifo_rddata_latch <= fifo_rddata;
    end

    // -------------------------------------------------------------------------
    // 保持寄存器直接驱动 WDATA；正常读延迟约定下，等待 WREADY 时不取下一字。
    // -------------------------------------------------------------------------
    assign m_axi_wdata =fifo_rddata_latch;

    // -------------------------------------------------------------------------
    // 15 WVALID 生成
    // 每一次数据握手均清零 WVALID；读数据返回后重新置位。
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if(reset)
            m_axi_wvalid <= 0;
        else if(
                (current_state == S_WR_DATA)&&
                m_axi_wvalid&&m_axi_wready

                )
            m_axi_wvalid <= 0;
        else if (fifo_rddata_valid)
            m_axi_wvalid <= 1;
        else
            m_axi_wvalid <= m_axi_wvalid;
    end

    // -------------------------------------------------------------------------
    // 16 WLAST 提前标记末拍
    // wr_data_cnt 为握手前已消费拍数；倒数第二拍握手时旧计数等于 AWLEN-1，
    // 从而置 WLAST，留给下一数据拍使用。末拍握手后清零，背压期间保持。
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if(reset)
            m_axi_wlast <= 0;
        else if((current_state == S_WR_DATA)&&m_axi_wvalid&&m_axi_wready&&m_axi_wlast)
            m_axi_wlast <= 0;
        else if((wr_data_cnt==(AXI_BURST_LEN-1))&&m_axi_wvalid&&m_axi_wready)
            m_axi_wlast <= 1;
        else
            m_axi_wlast <= m_axi_wlast;
    end

    // -------------------------------------------------------------------------
    // 17 突发内数据拍计数
    // 复位及 IDLE 清零，仅在 WVALID 与 WREADY 同时有效时加一。
    // 计数读取遵循 NBA 旧值语义；保留原有 1+wr_data_cnt 表达式和自赋值。
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if(reset)
            wr_data_cnt <= 0;
        else if(current_state == S_IDLE)
            wr_data_cnt <= 0;
        else if(m_axi_wready && m_axi_wvalid)
            wr_data_cnt <= 1+wr_data_cnt;
        else
            wr_data_cnt <= wr_data_cnt;
    end
endmodule
