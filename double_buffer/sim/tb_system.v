// =============================================================================
//  双缓�? —�?? 系统级仿真（总工程）
//
//  验证整条数据链路�?
//     摄像头源 �? 写FIFO �? AXI写主�? �? [DDR3] �? AXI读主�? �? 读FIFO �? 显示接收
//
//  被测：真实的 rtl/fifo_to_adapter.v（模块名 fifo_axi4_adapter�?
//        = 乒乓控制�? + 两个异步FIFO + 两个 AXI4 主机，即双缓存的全部核心
//
//  为了"仿真�? + 好读"，以下三部分用行为级模型替代�?
//     · DDR3/MIG    �?  axi 从端模型（存得进、读得出即可�?
//     · 摄像头芯�?  �?  cam_src 像素源（省掉 252 �? I2C 配置，仿真从分钟级降到秒级）
//     · HDMI 时序   �?  disp 接收模型（省�? 74.25MHz 完整行场时序�?
// =============================================================================
`timescale 1ns / 1ps
module tb_system;

// ==================================================================
// 0. 参数
// ==================================================================
localparam IMG_W   = 64;              // 图像缩小：每帧仅 8 个突发（真实 1280x720 �? 3600�?
localparam IMG_H   = 32;
localparam A_BASE  = 32'h0100_0000;   // A 区基�?
localparam B_BASE  = 32'h0120_0000;   // B 区基�?
localparam NFRAME  = 8;               // �? 8 帧足够判�?
localparam SEL_BIT = 21;              //  A/B 判别位：0=A�? 1=B�?

// ==================================================================
// 1. 时钟与复位（三个时钟域，与真实工程一致）
// ==================================================================
reg ui_clk = 1'b0;  always #5     ui_clk = ~ui_clk;   // 100 MHz  AXI / 乒乓控制器域
reg wr_clk = 1'b0;  always #6     wr_clk = ~wr_clk;   // ~83 MHz  摄像头像素时钟域
reg rd_clk = 1'b0;  always #6.734 rd_clk = ~rd_clk;   // 74.25 MHz 显示�?

reg reset      = 1'b1;
reg wrfifo_rst = 1'b1;
reg rdfifo_rst = 1'b1;

// ==================================================================
// 2. 全部线网声明（集中放在最前，避免隐式声明冲突�?
// ==================================================================
// --- �? FIFO 用户侧（摄像头域�?---
wire        fifo_full;
wire [10:0] wr_data_count;

// --- �? FIFO 用户侧（显示域）---
wire        fifo_empty;
wire [15:0] fifo_dout;
wire [10:0] rd_data_count;
wire        rd_en;                    // 显示接收读使�?

// --- AXI 写地�?通道 ---
wire [3:0]  m_axi_awid;
wire [31:0] m_axi_awaddr;
wire [7:0]  m_axi_awlen;
wire [2:0]  m_axi_awsize;
wire [1:0]  m_axi_awburst;
wire        m_axi_awlock;
wire [3:0]  m_axi_awcache;
wire [2:0]  m_axi_awprot;
wire [3:0]  m_axi_awqos;
wire [3:0]  m_axi_awregion;
wire        m_axi_awvalid, m_axi_awready;

// --- AXI 写数据�?�道 ---
wire [127:0] m_axi_wdata;
wire [15:0]  m_axi_wstrb;
wire         m_axi_wlast, m_axi_wvalid, m_axi_wready;

// --- AXI 写响应�?�道 ---
wire [3:0]   m_axi_bid;
wire [1:0]   m_axi_bresp;
wire         m_axi_bvalid, m_axi_bready;

// --- AXI 读地�?通道 ---
wire [3:0]  m_axi_arid;
wire [31:0] m_axi_araddr;
wire [7:0]  m_axi_arlen;
wire [2:0]  m_axi_arsize;
wire [1:0]  m_axi_arburst;
wire        m_axi_arlock;
wire [3:0]  m_axi_arcache;
wire [2:0]  m_axi_arprot;
wire [3:0]  m_axi_arqos;
wire [3:0]  m_axi_arregion;
wire        m_axi_arvalid, m_axi_arready;

// --- AXI 读数据�?�道 ---
wire [3:0]   m_axi_rid;
wire [127:0] m_axi_rdata;
wire [1:0]   m_axi_rresp;
wire         m_axi_rlast, m_axi_rvalid, m_axi_rready;

wire         camera_w_done;

// ==================================================================
// 3. 摄像头源模型：连续产生�?�增 16bit 像素，写 FIFO 满则暂停
// ==================================================================
reg [15:0] cam_din   = 16'd0;
reg        cam_wr_en = 1'b0;

always @(posedge wr_clk or posedge reset) begin
    if (reset) begin
        cam_din   <= 16'd0;
        cam_wr_en <= 1'b0;
    end else if (!fifo_full) begin
        cam_wr_en <= 1'b1;
        cam_din   <= cam_din + 1'b1;     // 像素值�?�增，便于判断数据�?�路是否打�??
    end else begin
        cam_wr_en <= 1'b0;
    end
end

// ==================================================================
// 4. 行为�? DDR3：AXI4 从端（AW/W/B + AR/R�?
// ==================================================================
reg [127:0] mem [0:16383];             // 用地�?�? 18 位索引，够覆�? A/B 两区

integer k;                             // 初始化为 0，避�?"尚未写入的区�?"读出 X
initial for (k = 0; k < 16384; k = k + 1) mem[k] = 128'd0;

// ---- 4.1 写�?�道 ----
reg        wr_busy  = 1'b0;
reg [31:0] wr_addr;
reg [7:0]  wr_beats;
reg        bvalid_r = 1'b0;

assign m_axi_awready = !wr_busy;
assign m_axi_wready  =  wr_busy;

always @(posedge ui_clk or posedge reset) begin
    if (reset) begin
        wr_busy  <= 1'b0;
        bvalid_r <= 1'b0;
    end else begin
        if (m_axi_awvalid && m_axi_awready) begin
            wr_addr  <= m_axi_awaddr;
            wr_beats <= m_axi_awlen;
            wr_busy  <= 1'b1;
        end else if (wr_busy && m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
            wr_busy  <= 1'b0;
        end
        // wlast 之后的下�?拍回 B 响应
        bvalid_r <= (wr_busy && m_axi_wvalid && m_axi_wready && m_axi_wlast);
    end
end

always @(posedge ui_clk) begin
    if (wr_busy && m_axi_wvalid && m_axi_wready) begin
        mem[wr_addr[17:4]] <= m_axi_wdata;   // 128bit = 16 字节，地�?步进 16
        wr_addr            <= wr_addr + 16;
    end
end

assign m_axi_bvalid = bvalid_r;
assign m_axi_bid    = 4'd0;
assign m_axi_bresp  = 2'b00;                 // �? OKAY

// ---- 4.2 读�?�道 ----
reg        rd_busy  = 1'b0;
reg        rvalid_r = 1'b0;
reg [31:0] rd_addr;
reg [7:0]  rd_beats, rbeat;

assign m_axi_arready = !rd_busy;

always @(posedge ui_clk or posedge reset) begin
    if (reset) begin
        rd_busy  <= 1'b0;
        rvalid_r <= 1'b0;
    end else begin
        if (m_axi_arvalid && m_axi_arready) begin
            rd_addr  <= m_axi_araddr;
            rd_beats <= m_axi_arlen;
            rd_busy  <= 1'b1;
            rvalid_r <= 1'b1;
            rbeat    <= 8'd0;
        end else if (rd_busy && rvalid_r && m_axi_rready) begin
            if (rbeat == rd_beats) begin
                rd_busy  <= 1'b0;
                rvalid_r <= 1'b0;
            end else begin
                rbeat   <= rbeat + 1'b1;
                rd_addr <= rd_addr + 16;
            end
        end
    end
end

assign m_axi_rvalid = rd_busy && rvalid_r;
assign m_axi_rlast  = rd_busy && rvalid_r && (rbeat == rd_beats);
assign m_axi_rdata  = mem[rd_addr[17:4]];
assign m_axi_rid    = 4'd0;
assign m_axi_rresp  = 2'b00;
assign m_axi_rready = 1'b1;                  // 显示侧恒可接�?

// ==================================================================
// 5. 显示接收模型：读 FIFO 非空就取，模�? HDMI 逐像素消�?
// ==================================================================
assign rd_en = !fifo_empty;

// ==================================================================
// 6. 被测设计：真实的双缓存核心（fifo_axi4_adapter�?
// ==================================================================
fifo_axi4_adapter #(
    .FIFO_DW         (16),
    .FIFO_ADDR_WIDTH (8),
    .BUF_A_BEGIN     (A_BASE),
    .BUF_B_BEGIN     (B_BASE),
    .AXI_DATA_WIDTH  (128),
    .AXI_ADDR_WIDTH  (32),
    .AXI_ID_WIDTH    (4),
    .CAMERA_AXI_ID   (0),
    .AXI_BURST_LEN   (31),
    .IMAGE_WIDTH     (IMG_W),
    .IMAGE_HEIGHT    (IMG_H)
) u_dut (
    .ui_clk        (ui_clk),
    .reset         (reset),

    // 写侧（摄像头域）
    .wr_clk        (wr_clk),
    .din           (cam_din),
    .wr_en         (cam_wr_en),
    .wrfifo_rst    (wrfifo_rst),
    .full          (fifo_full),
    .wr_data_count (wr_data_count),

    // 读侧（显示域�?
    .rd_clk        (rd_clk),
    .rdfifo_rst    (rdfifo_rst),
    .rd_en         (rd_en),
    .dout          (fifo_dout),
    .empty         (fifo_empty),
    .rd_data_count (rd_data_count),

    // AXI 写地�?通道
    .m_axi_awid    (m_axi_awid),     .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),  .m_axi_awlock  (m_axi_awlock),
    .m_axi_awcache (m_axi_awcache),  .m_axi_awprot  (m_axi_awprot),
    .m_axi_awqos   (m_axi_awqos),    .m_axi_awregion(m_axi_awregion),
    .m_axi_awvalid (m_axi_awvalid),  .m_axi_awready (m_axi_awready),

    // AXI 写数据�?�道
    .m_axi_wdata   (m_axi_wdata),    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wlast   (m_axi_wlast),    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),

    // AXI 写响应�?�道
    .m_axi_bid     (m_axi_bid),      .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),   .m_axi_bready  (m_axi_bready),

    // AXI 读地�?通道
    .m_axi_arid    (m_axi_arid),     .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),  .m_axi_arlock  (m_axi_arlock),
    .m_axi_arcache (m_axi_arcache),  .m_axi_arprot  (m_axi_arprot),
    .m_axi_arqos   (m_axi_arqos),    .m_axi_arregion(m_axi_arregion),
    .m_axi_arvalid (m_axi_arvalid),  .m_axi_arready (m_axi_arready),

    // AXI 读数据�?�道
    .m_axi_rid     (m_axi_rid),      .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rvalid  (m_axi_rvalid),   .m_axi_rready  (m_axi_rready),

    .camera_w_done (camera_w_done)
);

// ==================================================================
// 7. 判定（仿真看�?么信�?"都在这里�?
// ==================================================================
wire wsel = m_axi_awaddr[SEL_BIT];    // 写端当前�? A(0) / B(1)
wire rsel = m_axi_araddr[SEL_BIT];    // 读端当前�? A(0) / B(1)

integer e_alt_w = 0;    // CHK1 写缓冲未逐帧交替
integer e_alt_r = 0;    // CHK2 读缓冲未交替
integer e_same  = 0;    // CHK3 读写同区（会撕裂�?
integer e_x     = 0;    // CHK4 读出数据�? X/Z
integer e_stuck = 0;    // CHK5 写地�?停滞（同�?帧内重复写同�?地址�?

integer frame_no   = 0;
reg     started    = 1'b0;
reg     last_wsel  = 1'b0, have_wsel = 1'b0;
reg     last_rsel  = 1'b0, have_rsel = 1'b0;

// CHK1：每帧写完（camera_w_done）时，该帧所用缓冲应与上�?帧不�?
always @(posedge ui_clk) begin
    if (camera_w_done) begin
        frame_no  <= frame_no + 1;
        started   <= 1'b1;
        if (have_wsel && (wsel == last_wsel)) e_alt_w = e_alt_w + 1;
        last_wsel <= wsel;
        have_wsel <= 1'b1;
    end
end

// CHK2：读地址�?选的缓冲，必须等于控制器里的 r_buf（一致�?�）
//   两点说明�?
//   a) 另一块无新帧时读者会【重复当前帧】，此时 r_buf 本就不变，不算错误；
//   b) r_buf �? r_brust_complete 当拍就翻转，而读地址要�?�打�?拍后】才重载新基�?�?
//      因此交换瞬间存在�? 1 拍的过渡窗口（此时并未发起新突发，无害）�?
//      �? 下面�? 4 拍宽限期，跳过这个窗口再判一致�?��??
reg [2:0] rbc_gap = 3'd0;
always @(posedge ui_clk) begin
    if (u_dut.r_brust_complete) rbc_gap <= 3'd4;
    else if (rbc_gap != 3'd0)   rbc_gap <= rbc_gap - 1'b1;
end
always @(posedge ui_clk) begin
    if (started && (rbc_gap == 3'd0) && (rsel !== u_dut.r_buf)) e_alt_r = e_alt_r + 1;
end

// CHK3：不变式 —�?? 只在【读侧已启动 �? 写侧活跃】时才要�? w_buf != r_buf�?
//       解释：重构后 wr_wait 改为 frame_ready；frame_ready=1 表示写端停下等待
//       （此�? w_buf==r_buf 无害）�?�读侧未启动(frame_active=0)时也不检查�??
always @(posedge ui_clk) begin
    if (u_dut.frame_active && !u_dut.frame_ready &&
        (u_dut.w_buf == u_dut.r_buf)) e_same = e_same + 1;
end

// CHK4：读出数据不得为 X/Z
always @(posedge rd_clk) begin
    if (!fifo_empty && (^fifo_dout === 1'bx)) e_x = e_x + 1;
end

// CHK5 �?关键：同�?帧内，每次突发的写地�?必须【�?�增且不重复】�??
//       若基�?被在每个突发重装，地�?会一直停在基�? �? 整帧只写出头 512B�?
//       其余区域从未写入，上板表现为满屏垃圾彩条（这次实际踩到的坑）�?
reg [31:0] last_aw = 32'd0;
reg        have_last_aw = 1'b0;
always @(posedge ui_clk) begin
    if (m_axi_awvalid && m_axi_awready) begin
        if (have_last_aw && (m_axi_awaddr == last_aw)) e_stuck = e_stuck + 1;
        last_aw      <= m_axi_awaddr;
        have_last_aw <= 1'b1;
    end
    if (camera_w_done) have_last_aw <= 1'b0;    // 新帧�?始，重新比较
end

// ==================================================================
// 8. 结束与输�?
// ==================================================================
reg done = 1'b0;
always @(posedge ui_clk) if (!done && frame_no >= NFRAME) done <= 1'b1;

always @(posedge ui_clk) if (done) begin
    $display("");
    $display("===== 双缓�? 系统级仿�? =====");
    $display("CHK1 写缓冲未逐帧交替 (awaddr[21])  : %0d", e_alt_w);
    $display("CHK2 读缓冲未交替     (araddr[21])  : %0d", e_alt_r);
    $display("CHK3 读写落在同一缓冲 (w_buf==r_buf): %0d", e_same);
    $display("CHK4 读出数据出现 X/Z               : %0d", e_x);
    $display("CHK5 写地�?停滞(基址被反复重�?)     : %0d", e_stuck);
    if ((e_alt_w + e_alt_r + e_same + e_x + e_stuck) == 0)
        $display("===== 结果: PASS  双缓存系统链路正�? =====");
    else
        $display("===== 结果: FAIL  双缓存系统链路异�? =====");
    $finish;
end

initial begin
    #300;                               // 先保持复�?
    reset      = 1'b0;
    wrfifo_rst = 1'b0;
    rdfifo_rst = 1'b0;
    #2000000;                           // 保险超时
    $display("===== 结果: TIMEOUT =====");
    $finish;
end

endmodule
