// 模块名: udp_rx  功能: UDP接收解析 + 回显数据FIFO + 校验和验证
// 报文结构: 0~1源端口 | 2~3目的端口 | 4~5 UDP长度 | 6~7校验和 | 8~数据
// 校验和: 伪首部(源IP+目的IP+协议0x11+UDP长度)+UDP头+数据, 反码求和须为0xFFFF
module udp_rx #(
    parameter [31:0] BOARD_IP       = 32'hC0A8_017B,
    parameter [15:0] LOCAL_UDP_PORT = 16'h1388
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        p_sof,
    input  wire        p_en,
    input  wire        p_eof,
    input  wire [7:0]  p_data,
    input  wire [15:0] payload_len,
    input  wire [31:0] src_ip,
    input  wire [47:0] src_mac,
    input  wire        ip_ok,
    output reg         pkt_en,
    output reg  [15:0] sport,
    output reg  [15:0] udp_len,
    output reg  [31:0] rip,
    output reg  [47:0] rmac,
    input  wire        fifo_rd,
    output wire [7:0]  fifo_dout,
    output wire        fifo_empty
);

    //------------------------------------------------------------------
    // UDP回显数据FIFO
    //------------------------------------------------------------------
    wire        fifo_wr;
    wire [7:0]  fifo_din;
    wire        fifo_clr;
    //------------------------------------------------------------------
    // 回显数据 FIFO: 深度 2048 覆盖 1500 MTU(最大回显数据 1472 字节),
    // 并由 fifo_full 对写侧反压。rd_data_count 位宽取 12。
    //------------------------------------------------------------------
    wire [11:0] fifo_cnt;
    wire        fifo_full;
    // XPM 同步FIFO: Vivado原生FIFO IP, FWFT(首字直通)模式, 免.xci文件
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE ("auto"),
        .FIFO_WRITE_DEPTH (2048),
        // rd_data_count 位宽须显式指定为 12, 否则仅 1 位(内部计数最高位),
        // 残留数据清理逻辑会失效。
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
    // cnt 用 11 位, 上限 1517 覆盖最大帧长, 避免长度计数饱和。
    reg [10:0] cnt;
    reg [15:0] sport_r, dport_r, len_r, cks_r;
    reg [31:0] acc;
    reg [7:0]  hi_byte;
    reg        pseudo_done;
    reg        ck_ok;
    reg        port_ok;
    reg        parsed;
    reg        clr_pend;

    // 写使能带 fifo_full 反压
    assign fifo_wr  = p_en && !p_sof && (cnt >= 11'd8) && port_ok && !clr_pend
                      && !fifo_full;
    assign fifo_din = p_data;
    assign fifo_clr = clr_pend;

    wire [16:0] fold1 = acc[31:16] + acc[15:0];
    wire [16:0] fold2 = {1'b0, fold1[15:0]} + {16'd0, fold1[16]};

    // 伪首部累加和: 源IP+目的IP+协议(0x0011)+UDP长度
    wire [17:0] pseudo_sum = {2'b00, src_ip[31:16]} + {2'b00, src_ip[15:0]}
                           + {2'b00, BOARD_IP[31:16]} + {2'b00, BOARD_IP[15:0]}
                           + 18'h0011 + {2'b00, len_r};

    always @(posedge clk) begin
        if (rst) begin
            cnt <= 11'd0; sport_r <= 16'd0; dport_r <= 16'd0;
            len_r <= 16'd0; cks_r <= 16'd0;
            acc <= 32'd0; hi_byte <= 8'd0;
            pseudo_done <= 1'b0; ck_ok <= 1'b0;
            port_ok <= 1'b0; parsed <= 1'b0; clr_pend <= 1'b0;
            pkt_en <= 1'b0; sport <= 16'd0; udp_len <= 16'd0;
            rip <= 32'd0; rmac <= 48'd0;
        end else begin
            pkt_en   <= 1'b0;
            clr_pend <= 1'b0;

            if (p_sof) begin
                sport_r[15:8] <= p_data; // 载荷首字节(偏移0=源端口高字节)
                hi_byte <= p_data;       // 偏移0为偶数位: 校验和高字节
                acc <= 32'd0;
                cnt <= 11'd1; parsed <= 1'b0;
                port_ok <= 1'b0; pseudo_done <= 1'b0; ck_ok <= 1'b0;
                if (fifo_cnt != 12'd0)
                    clr_pend <= 1'b1;    // 清残留
            end else if (p_en) begin
                case (cnt)
                    11'd1: sport_r[7:0]  <= p_data;
                    11'd2: dport_r[15:8] <= p_data;
                    11'd3: dport_r[7:0]  <= p_data;
                    11'd4: len_r[15:8]   <= p_data;
                    11'd5: len_r[7:0]    <= p_data;
                    11'd6: cks_r[15:8]   <= p_data;
                    11'd7: cks_r[7:0]    <= p_data;
                    default: ;
                endcase
                // 目的端口匹配才收(cnt==6时dport两字节均已锁存)
                if (cnt == 11'd6)
                    port_ok <= (dport_r == LOCAL_UDP_PORT);
                // 校验和: cnt==7时把伪首部一并累加(只加一次)
                if (cnt[0] == 1'b0) begin
                    hi_byte <= p_data;
                    // 校验和按 16 位字累加: 长度为奇数时末字节按 RFC768
                    // 补 0x00 组成末字再累加。
                    if (p_eof)
                        acc <= acc + {8'd0, p_data, 8'h00};
                end else if (cnt == 11'd7) begin
                    acc <= acc + pseudo_sum + {8'd0, hi_byte, p_data};
                    pseudo_done <= 1'b1;
                end else begin
                    acc <= acc + {8'd0, hi_byte, p_data};
                end
                if (cnt == 11'd7)
                    parsed <= 1'b1;
                // cnt 上限 1517, 覆盖最大帧长
                if (cnt < 11'd1517)
                    cnt <= cnt + 11'd1;
            end else if (ip_ok) begin
                // 提交: 端口匹配+校验通过+长度合法 -> 请求回显
                //
                // ip_rx 末字节同拍置起 p_en 与 p_eof, 故校验和判定放在
                // ip_ok 提交时用组合折叠结果(IPv4 下 UDP 校验和可为 0)。
                if (parsed && port_ok
                    && ((fold2[15:0] == 16'hFFFF) || (cks_r == 16'h0000))
                    && payload_len >= 16'd8 && len_r == payload_len) begin
                    pkt_en  <= 1'b1;
                    sport   <= sport_r;   // 回显目的端口=发送方端口
                    udp_len <= len_r;     // 长度原样返回
                    rip     <= src_ip;
                    rmac    <= src_mac;
                end else begin
                    clr_pend <= 1'b1;     // 不合格: 丢弃
                end
            end
        end
    end

endmodule
