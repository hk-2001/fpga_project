//============================================================================
// 模块名   : icmp_tx
// 功能     : ICMP Echo应答发送: 组帧 MAC头+IP头+ICMP头+数据+FCS
// 组帧布局 : 帧内偏移
//            0~5 目的MAC | 6~11 本板MAC | 12~13 0x0800
//            14~33 IPv4首部 | 34 类型=0(应答) | 35 代码=0
//            36~37 校验和(复用请求的) | 38~39 ID | 40~41 SEQ
//            42~ 数据(读FIFO) | 最后4字节 FCS
//============================================================================
module icmp_tx #(
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP  = 32'hC0A8_017B
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        reply_en,
    input  wire [15:0] id,
    input  wire [15:0] seq,
    input  wire [15:0] icmp_cksum,
    input  wire [15:0] data_len,
    input  wire [47:0] dst_mac,
    input  wire [31:0] dst_ip,
    output reg         req,
    input  wire        grant,
    output reg         done,
    output reg         tx_en,
    output wire [7:0]  tx_data,
    output wire        fifo_rd,
    input  wire [7:0]  fifo_dout,
    input  wire        fifo_empty
);

    localparam S_IDLE = 2'd0,   // 空闲: 等待发送请求
               S_WAIT = 2'd1,   // 等待仲裁器授权
               S_SEND = 2'd2;   // 发送中(含最后的FCS)

    reg [1:0]  state;
    reg [15:0] id_r, seq_r, cks_r, dlen_r;
    reg [47:0] dmac_r;
    reg [31:0] dip_r;
    reg [15:0] ipck_r;       // IP首部校验和(请求到来时预算好)
    reg [10:0] bcnt;         // 当前发送字节在帧内的偏移
    reg [10:0] total;        // 帧总字节数 = 42 + 数据 + 4

    wire [15:0] ip_total_len = 16'd28 + dlen_r;   // IP头20+ICMP头8+数据

    //------------------------------------------------------------------
    // IP首部校验和: 字段固定, 直接用组合函数一次算完
    //------------------------------------------------------------------
    function [15:0] ip_hdr_cksum;
        input [15:0] tot_len;
        input [31:0] dip;
        reg [17:0] s;
        begin
            s = 18'h4500  + {2'b00, tot_len} + 18'h0000
              + 18'h4000 + {10'h000, 8'h40, 8'h01} + 18'h0000
              + {2'b00, BOARD_IP[31:16]} + {2'b00, BOARD_IP[15:0]}
              + {2'b00, dip[31:16]}      + {2'b00, dip[15:0]};
            s = {2'b00, s[15:0]} + {14'h0, s[17:16]};   // 进位回卷1
            s = {2'b00, s[15:0]} + {14'h0, s[17:16]};   // 进位回卷2
            ip_hdr_cksum = ~s[15:0];
        end
    endfunction

    //------------------------------------------------------------------
    // 应答ICMP校验和 = 请求校验和 + 0x0800 (反码加法, 进位回卷)
    //   依据: 请求与应答仅 Type/Code 这个16位字不同(0x0800 -> 0x0000),
    //         反码和减少0x0800, 取反后校验和增加0x0800。
    //   前提: icmp_rx 已验证请求校验和有效(fold2==0xFFFF)后才发 reply_en。
    //------------------------------------------------------------------
    function [15:0] reply_cksum;
        input [15:0] req_ck;
        reg [16:0] s;
        begin
            s = {1'b0, req_ck} + 17'h0800;
            if (s[16])
                s = {1'b0, s[15:0]} + 17'h0001;   // 反码进位回卷
            reply_cksum = s[15:0];
        end
    endfunction

    //------------------------------------------------------------------
    // 发送字节选择: 根据bcnt从各字段/FIFO/CRC中选出当前字节
    //------------------------------------------------------------------
    wire [10:0] data_last = 11'd41 + {1'b0, dlen_r};   // 最后一个数据字节偏移
    reg  [7:0] byte_sel;
    wire [31:0] crc_fcs;

    always @(*) begin
        if (bcnt < 10'd6)                       // 目的MAC
            byte_sel = dmac_r >> ((5 - bcnt[2:0]) * 8);
        else if (bcnt < 10'd12)                 // 源MAC(本板)
            byte_sel = BOARD_MAC >> ((11 - bcnt[3:0]) * 8);
        else 
        case (bcnt)
            10'd12: byte_sel = 8'h08;           // 以太网类型=IP
            10'd13: byte_sel = 8'h00;
            10'd14: byte_sel = 8'h45;           // 版本|首部长度
            10'd15: byte_sel = 8'h00;           // 服务类型
            10'd16: byte_sel = ip_total_len[15:8];
            10'd17: byte_sel = ip_total_len[7:0];
            10'd18: byte_sel = 8'h00;           // 标识
            10'd19: byte_sel = 8'h00;
            10'd20: byte_sel = 8'h40;           // 标志: 不分片
            10'd21: byte_sel = 8'h00;
            10'd22: byte_sel = 8'h40;           // TTL=64
            10'd23: byte_sel = 8'h01;           // 协议=ICMP
            10'd24: byte_sel = ipck_r[15:8];    // IP首部校验和
            10'd25: byte_sel = ipck_r[7:0];
            10'd26: byte_sel = BOARD_IP[31:24]; // 源IP=本板
            10'd27: byte_sel = BOARD_IP[23:16];
            10'd28: byte_sel = BOARD_IP[15:8];
            10'd29: byte_sel = BOARD_IP[7:0];
            10'd30: byte_sel = dip_r[31:24];    // 目的IP
            10'd31: byte_sel = dip_r[23:16];
            10'd32: byte_sel = dip_r[15:8];
            10'd33: byte_sel = dip_r[7:0];
            10'd34: byte_sel = 8'h00;           // ICMP类型=0(应答)
            10'd35: byte_sel = 8'h00;           // 代码
            10'd36: byte_sel = cks_r[15:8];     // ICMP校验和(复用)
            10'd37: byte_sel = cks_r[7:0];
            10'd38: byte_sel = id_r[15:8];      // 标识符
            10'd39: byte_sel = id_r[7:0];
            10'd40: byte_sel = seq_r[15:8];     // 序列号
            10'd41: byte_sel = seq_r[7:0];
            default:                            // 数据区或FCS区
                // data_last 即最后一个数据字节, 该拍必须取 FIFO 数据
                if (bcnt <= data_last)
                    byte_sel = fifo_dout;       // 来自FIFO
                else
                    byte_sel = crc_fcs >> ((bcnt - data_last - 1) * 8);
        endcase
    end

    assign tx_data = byte_sel;

    // CRC: 校验范围=整个帧(除FCS本身)
    crc32_d8 u_crc32 (
        .clk     (clk),
        .rst     (rst),
        .data    (tx_data),
        .data_en (tx_en && (bcnt < total - 10'd4)),
        .crc_out (crc_fcs),
        .crc_ok  ()
    );

    // FIFO读: 仅在数据区且未授权前不发读
    assign fifo_rd = tx_en && (bcnt >= 10'd42) && (bcnt <= data_last)
                     && !fifo_empty;

    //------------------------------------------------------------------
    // 发送状态机
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;  req <= 1'b0;  done <= 1'b0;
            tx_en <= 1'b0;    bcnt <= 11'd0; total <= 11'd0;
            id_r <= 16'd0; seq_r <= 16'd0; cks_r <= 16'd0; dlen_r <= 16'd0;
            dmac_r <= 48'd0; dip_r <= 32'd0; ipck_r <= 16'd0;
        end else begin
            done <= 1'b0;                    // done为单拍脉冲
            case (state)
                S_IDLE: begin
                    if (reply_en) begin
                        // 锁存本次应答所需的全部信息
                        id_r   <= id;
                        seq_r  <= seq;
                        cks_r  <= reply_cksum(icmp_cksum);
                        dlen_r <= data_len;
                        dmac_r <= dst_mac;
                        dip_r  <= dst_ip;
                        // IP首部校验和现在就算好, 发送时直接取
                        ipck_r <= ip_hdr_cksum(16'd28 + data_len, dst_ip);
                        total  <= 11'd42 + {1'b0, data_len} + 11'd4;
                        req    <= 1'b1;      // 向仲裁器申请总线
                        state  <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (grant) begin
                        bcnt <= 11'd0;       // 从第0字节开始发
                        tx_en <= 1'b1;
                        state <= S_SEND;
                    end
                end
                S_SEND: begin
                    if (bcnt == total - 11'd1) begin
                        tx_en <= 1'b0;       // 最后一个FCS字节发完
                        done  <= 1'b1;       // 通知仲裁器释放
                        req   <= 1'b0;
                        state <= S_IDLE;
                    end else begin
                        bcnt <= bcnt + 11'd1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
