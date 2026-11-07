`timescale 1ns / 1ps
//============================================================================
// 文件     : xpm_fifo_sync_sim.v  (仅用于仿真, 非综合文件)
// 功能     : 行为级 FWFT 同步 FIFO, 用于替代真实的 xpm_fifo_sync 原语,
//            让不支持 XPM 的仿真器(以及本机 xsim 流程)也能编译运行本工程。
//            综合时 Vivado 会自动解析真实 XPM, 该模型不参与综合。
//
// rd_data_count 位宽定为 12 位:
//   rtl 中两处 FIFO 深度已加深到 2048, 计数值最大为 2048,
//   需要 ceil(log2(2048))+1 = 12 位; 若仍用 11 位, 满(2048)时会被截断成 0。
//
// 端口名需与 rtl 中的例化保持一致, 否则编译失败:
//     clk           -> 应为 wr_clk       (XPM 同步FIFO端口名)
//     data_count    -> 应为 rd_data_count
//     injectsbiterra-> 拼写错误, 应为 injectsbiterr
//     injectdbiterra-> 拼写错误, 应为 injectdbiterr
//   另外 empty_w 未声明就被 assign 使用。
//   现已全部按 rtl/icmp/icmp_rx.v 与 rtl/udp/udp_rx.v 的例化端口名对齐。
//============================================================================
module xpm_fifo_sync #(
    parameter FIFO_MEMORY_TYPE    = "auto",
    parameter FIFO_WRITE_DEPTH    = 1024,
    // 真实 xpm_fifo_sync 的 rd_data_count 位宽由本参数决定
    //   (默认仅 1 位), rtl 中已显式设为 12(2048 深度).
    //   本行为模型固定按 12 位输出真实计数值, 故该参数在此仅用于"接口对齐",
    //   声明但不参与内部逻辑 —— 这样仿真与综合的例化写法完全一致。
    parameter integer RD_DATA_COUNT_WIDTH = 12,
    parameter WRITE_DATA_WIDTH    = 8,
    parameter READ_DATA_WIDTH     = 8,
    parameter READ_MODE           = "fwft",
    parameter USE_ADV_FEATURES    = "0707"
)(
    input  wire                        wr_clk,
    input  wire                        rst,
    input  wire                        wr_en,
    input  wire [WRITE_DATA_WIDTH-1:0] din,
    input  wire                        rd_en,
    output reg  [READ_DATA_WIDTH-1:0]  dout,
    output wire                        full,
    output reg                         empty,
    output wire [11:0]                 rd_data_count,   // 2048 深度 -> 12 位
    output wire                        almost_full,
    output wire                        almost_empty,
    output wire                        prog_full,
    output wire                        prog_empty,
    output reg                         data_valid,
    output wire                        wr_ack,
    output wire                        overflow,
    output wire                        underflow,
    input  wire                        sleep,
    input  wire                        injectsbiterr,
    input  wire                        injectdbiterr,
    output reg                         wr_rst_busy,
    output reg                         rd_rst_busy
);

    localparam AW = $clog2(FIFO_WRITE_DEPTH);

    reg [READ_DATA_WIDTH-1:0] mem [0:FIFO_WRITE_DEPTH-1];
    reg [AW:0] wptr;
    reg [AW:0] rptr;

    wire empty_w = (wptr == rptr);        // 必须显式声明为 wire

    assign full         = (wptr[AW] != rptr[AW]) && (wptr[AW-1:0] == rptr[AW-1:0]);
    assign rd_data_count = wptr - rptr;
    assign almost_full  = full;
    assign almost_empty = empty_w;
    assign prog_full    = 1'b0;
    assign prog_empty   = 1'b0;
    assign wr_ack       = wr_en && !full;
    assign overflow     = wr_en && full;
    assign underflow    = rd_en && empty_w;

    // FWFT(首字直通): dout 上始终是队首数据
    always @(*) begin
        if (!empty_w)
            dout = mem[rptr[AW-1:0]];
        else
            dout = {READ_DATA_WIDTH{1'b0}};
    end

    always @(posedge wr_clk) begin
        if (rst) begin
            wptr <= 0; rptr <= 0;
            wr_rst_busy <= 1'b1; rd_rst_busy <= 1'b1;
            data_valid  <= 1'b0;
        end else begin
            wr_rst_busy <= 1'b0; rd_rst_busy <= 1'b0;
            if (wr_en && !full) begin
                mem[wptr[AW-1:0]] <= din;
                wptr <= wptr + 1'b1;
            end
            if (rd_en && !empty_w)
                rptr <= rptr + 1'b1;
            data_valid <= !empty_w;
        end
    end

    always @(*) empty = empty_w;

endmodule
