// udp_tx: UDP回显发送, 组帧 = MAC头 + IP头 + UDP头 + 数据(FIFO) + FCS
// IPv4下UDP校验和可置0(协议允许), IP首部校验和用function预算
module udp_tx #(
    parameter [47:0] BOARD_MAC      = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP       = 32'hC0A8_017B,
    parameter [15:0] LOCAL_UDP_PORT = 16'h1388
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        send_en,      // 来自udp_rx的回显请求
    input  wire [15:0] sport,        // 目的端口(=发送方源端口)
    input  wire [15:0] udp_len,      // UDP总长度(原样返回)
    input  wire [31:0] dst_ip,
    input  wire [47:0] dst_mac,
    output reg         req,
    input  wire        grant,
    output reg         done,
    output reg         tx_en,
    output wire [7:0]  tx_data,
    output wire        fifo_rd,
    input  wire [7:0]  fifo_dout,
    input  wire        fifo_empty
);

    localparam S_IDLE = 2'd0, S_WAIT = 2'd1, S_SEND = 2'd2;

    reg [1:0]  state;
    reg [15:0] sport_r, ulen_r;
    reg [47:0] dmac_r;
    reg [31:0] dip_r;
    reg [15:0] ipck_r;
    reg [10:0] bcnt, total;

    wire [15:0] ip_total_len = 16'd20 + ulen_r;      // IP头20 + UDP报文
    wire [10:0] data_last    = 11'd41 + {1'b0, ulen_r} - 11'd8;

    function [15:0] ip_hdr_cksum;
        input [15:0] tot_len;
        input [31:0] dip;
        reg [17:0] s;
        begin
            s = 18'h4500  + {2'b00, tot_len} + 18'h0000
              + 18'h4000 + {10'h000, 8'h40, 8'h11} + 18'h0000
              + {2'b00, BOARD_IP[31:16]} + {2'b00, BOARD_IP[15:0]}
              + {2'b00, dip[31:16]}      + {2'b00, dip[15:0]};
            s = {2'b00, s[15:0]} + {14'h0, s[17:16]};
            s = {2'b00, s[15:0]} + {14'h0, s[17:16]};
            ip_hdr_cksum = ~s[15:0];
        end
    endfunction

    // 发送字节选择
    reg [7:0] byte_sel;
    wire [31:0] crc_fcs;
    always @(*) begin
        if (bcnt < 11'd6)
            byte_sel = dmac_r >> ((5 - bcnt[2:0]) * 8);
        else if (bcnt < 11'd12)
            byte_sel = BOARD_MAC >> ((11 - bcnt[3:0]) * 8);
        else 
        case (bcnt)
            11'd12: byte_sel = 8'h08;
            11'd13: byte_sel = 8'h00;
            11'd14: byte_sel = 8'h45;
            11'd15: byte_sel = 8'h00;
            11'd16: byte_sel = ip_total_len[15:8];
            11'd17: byte_sel = ip_total_len[7:0];
            11'd18: byte_sel = 8'h00;
            11'd19: byte_sel = 8'h00;
            11'd20: byte_sel = 8'h40;
            11'd21: byte_sel = 8'h00;
            11'd22: byte_sel = 8'h40;
            11'd23: byte_sel = 8'h11;            // 协议=UDP
            11'd24: byte_sel = ipck_r[15:8];
            11'd25: byte_sel = ipck_r[7:0];
            11'd26: byte_sel = BOARD_IP[31:24];
            11'd27: byte_sel = BOARD_IP[23:16];
            11'd28: byte_sel = BOARD_IP[15:8];
            11'd29: byte_sel = BOARD_IP[7:0];
            11'd30: byte_sel = dip_r[31:24];
            11'd31: byte_sel = dip_r[23:16];
            11'd32: byte_sel = dip_r[15:8];
            11'd33: byte_sel = dip_r[7:0];
            11'd34: byte_sel = LOCAL_UDP_PORT[15:8];  // 源端口=本板5000
            11'd35: byte_sel = LOCAL_UDP_PORT[7:0];
            11'd36: byte_sel = sport_r[15:8];         // 目的端口
            11'd37: byte_sel = sport_r[7:0];
            11'd38: byte_sel = ulen_r[15:8];          // UDP长度
            11'd39: byte_sel = ulen_r[7:0];
            11'd40: byte_sel = 8'h00;                 // UDP校验和=0
            11'd41: byte_sel = 8'h00;
            default:
                // data_last 即最后一个数据字节, 该拍必须取 FIFO 数据
                if (bcnt <= data_last)
                    byte_sel = fifo_dout;
                else
                    byte_sel = crc_fcs >> ((bcnt - data_last - 1) * 8);
        endcase
    end

    assign tx_data = byte_sel;

    crc32_d8 u_crc32 (
        .clk(clk), .rst(rst),
        .data(tx_data),
        .data_en(tx_en && (bcnt < total - 11'd4)),
        .crc_out(crc_fcs)
    );

    assign fifo_rd = tx_en && (bcnt >= 11'd42) && (bcnt <= data_last)
                     && !fifo_empty;

    // 发送状态机(与icmp_tx结构一致)
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; req <= 1'b0; done <= 1'b0;
            tx_en <= 1'b0; bcnt <= 11'd0; total <= 11'd0;
            sport_r <= 16'd0; ulen_r <= 16'd0;
            dmac_r <= 48'd0; dip_r <= 32'd0; ipck_r <= 16'd0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (send_en) begin
                        sport_r <= sport;
                        ulen_r  <= udp_len;
                        dmac_r  <= dst_mac;
                        dip_r   <= dst_ip;
                        ipck_r  <= ip_hdr_cksum(16'd20 + udp_len, dst_ip);
                        total   <= 11'd38 + {1'b0, udp_len};  // 42+数据+4
                        req     <= 1'b1;
                        state   <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (grant) begin
                        bcnt <= 11'd0;
                        tx_en <= 1'b1;
                        state <= S_SEND;
                    end
                end
                S_SEND: begin
                    if (bcnt == total - 11'd1) begin
                        tx_en <= 1'b0;
                        done  <= 1'b1;
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
