//============================================================================
// 模块名   : icmp_rx
// 功能     : ICMP报文接收: 解析Echo请求(type=8), 校验ICMP校验和,
//            把请求的数据部分缓存进FIFO, 然后通知icmp_tx回Echo应答
// 报文结构 : IP载荷偏移
//            0 类型(8=请求,0=应答) | 1 代码(0) | 2~3 校验和
//            4~5 标识符ID | 6~7 序列号SEQ | 8~ 数据
// ICMP 校验和覆盖整个报文(从 Type 开始), 故应答校验和 = 请求校验和 + 0x0800
// (反码加法, 进位回卷): 请求 Type/Code 字为 0x0800, 应答为 0x0000。
//============================================================================
module icmp_rx(
    input  wire        clk,
    input  wire        rst,
    input  wire        p_sof,
    input  wire        p_en,
    input  wire        p_eof,
    input  wire [7:0]  p_data,
    input  wire [15:0] payload_len,
    input  wire        ip_ok,
    output reg         reply_en,
    output reg  [15:0] id,
    output reg  [15:0] seq,
    output reg  [15:0] icmp_cksum,
    output reg  [15:0] data_len,
    input  wire        fifo_rd,
    output wire [7:0]  fifo_dout,
    output wire        fifo_empty
);

    //------------------------------------------------------------------
    // ICMP数据缓存FIFO: 请求的数据先存起来, 应答时再读出发送
    //------------------------------------------------------------------
    wire        fifo_wr;
    wire [7:0]  fifo_din;
    wire        fifo_clr;
    //------------------------------------------------------------------
    // 回显数据 FIFO: 深度 2048 覆盖 1500 MTU(最大回显数据 1472 字节),
    // 并由 fifo_full 对写侧反压, 避免 FIFO 满后静默丢弃写操作。
    // rd_data_count 位宽 = ceil(log2(深度)) + 1 = 12。
    //------------------------------------------------------------------
    wire [11:0] fifo_cnt;
    wire        fifo_full;
    // XPM 同步FIFO: Vivado原生FIFO IP, FWFT(首字直通)模式, 免.xci文件
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE ("auto"),
        .FIFO_WRITE_DEPTH (2048),
        // rd_data_count 位宽需显式指定为 12; 默认 1 位时只取内部计数最高位,
        // fifo_cnt 几乎恒为 0, 残留数据清理逻辑会失效。
        // (USE_ADV_FEATURES[10] 启用该功能, 0x0707 已置位)
        .RD_DATA_COUNT_WIDTH (12),
        .WRITE_DATA_WIDTH (8),
        .READ_DATA_WIDTH  (8),
        .READ_MODE        ("fwft"),
        .USE_ADV_FEATURES ("0707")
    ) u_fifo (
        .wr_clk        (clk),
        .rst           (rst | fifo_clr),   // 复位与"丢弃错误报文"合并为高有效复位
        .wr_en         (fifo_wr),
        .din           (fifo_din),
        .rd_en         (fifo_rd),
        .dout          (fifo_dout),
        .full          (fifo_full),
        .empty         (fifo_empty),
        .rd_data_count (fifo_cnt),
        .almost_full   (),
        .almost_empty  (),
        .prog_full     (),
        .prog_empty    (),
        .data_valid    (),
        .wr_ack        (),
        .overflow      (),
        .underflow     (),
        .sleep         (1'b0),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0),
        .wr_rst_busy   (),
        .rd_rst_busy   ()
    );

    //------------------------------------------------------------------
    // cnt 用 11 位, 上限 1517 覆盖最大帧长, 避免长度计数饱和导致
    // 16 位字配对错乱。
    //------------------------------------------------------------------
    reg [10:0] cnt;
    reg [7:0]  type_r;
    reg [7:0]  code_r;
    reg [31:0] acc;
    reg [7:0]  hi_byte;
    reg        ck_ok;
    reg        parsed;
    reg        clr_pend;      // 待执行的清FIFO请求

    // 写使能带 fifo_full 反压
    assign fifo_wr  = p_en && !p_sof && (cnt >= 11'd8) && !clr_pend && !fifo_full;
    assign fifo_din = p_data;
    assign fifo_clr = clr_pend;

    // 反码折叠
    wire [16:0] fold1 = acc[31:16] + acc[15:0];
    wire [16:0] fold2 = {1'b0, fold1[15:0]} + {16'd0, fold1[16]};

    always @(posedge clk) begin
        if (rst) begin
            cnt <= 11'd0;  type_r <= 8'd0;  code_r <= 8'd0;
            acc <= 32'd0; hi_byte <= 8'd0;
            ck_ok <= 1'b0; parsed <= 1'b0; clr_pend <= 1'b0;
            reply_en <= 1'b0; id <= 16'd0; seq <= 16'd0;
            icmp_cksum <= 16'd0; data_len <= 16'd0;
        end else begin
            reply_en <= 1'b0;
            clr_pend <= 1'b0;

            if (p_sof) begin
                // 载荷首字节(偏移0=类型字段)与p_sof同拍到达
                type_r  <= p_data;
                hi_byte <= p_data;      // 偏移0为偶数位: 校验和高字节
                acc     <= 32'd0;
                cnt     <= 11'd1;
                parsed  <= 1'b0;
                // 新报文到来前, 丢弃上次未取走的残留数据
                if (fifo_cnt != 12'd0)
                    clr_pend <= 1'b1;
            end else if (p_en) begin
                case (cnt)
                    11'd1: code_r <= p_data;
                    11'd2: icmp_cksum[15:8] <= p_data;
                    11'd3: icmp_cksum[7:0]  <= p_data;
                    11'd4: id[15:8]  <= p_data;
                    11'd5: id[7:0]   <= p_data;
                    11'd6: seq[15:8] <= p_data;
                    11'd7: seq[7:0]  <= p_data;
                    default: ;
                endcase
                // 校验和覆盖整个ICMP报文(含头8字节和数据)
                // 校验和按 16 位字累加: 偶数偏移字节暂存 hi_byte, 与下一个
                // 奇数偏移字节配对累加; 长度为奇数时末字节按 RFC792 补 0x00。
                if (cnt[0] == 1'b0) begin
                    hi_byte <= p_data;
                    if (p_eof)
                        acc <= acc + {8'd0, p_data, 8'h00};
                end 
                else
                    acc <= acc + {8'd0, hi_byte, p_data};
                if (cnt == 11'd7)
                    parsed <= 1'b1;         // 头部已完整
                // cnt 上限 1517, 覆盖最大帧长
                if (cnt < 11'd1517)
                    cnt <= cnt + 11'd1;
            end else if (ip_ok) begin
                // 提交: 是Echo请求且校验通过 -> 请求发送应答
                //
                // ip_rx 在最后一个载荷字节那一拍同时置起 p_en 与 p_eof,
                // 互斥分支中 p_en 优先, 故校验和判定放在 ip_ok 提交时,
                // 用组合折叠结果(此时 acc 已累加完整个报文)。
                if (parsed && type_r == 8'd8 && code_r == 8'd0
                    && (fold2[15:0] == 16'hFFFF)      // 含校验和自身须为FFFF
                    && payload_len >= 16'd8) begin
                    reply_en <= 1'b1;
                    data_len <= payload_len - 16'd8;
                    // id/seq/icmp_cksum 已在解析时锁存, 直接输出
                end else begin
                    clr_pend <= 1'b1;       // 非Echo请求或校验失败: 丢数据
                end
            end
        end
    end

endmodule
