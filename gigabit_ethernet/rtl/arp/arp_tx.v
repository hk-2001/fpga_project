// arp_tx: ARP应答发送(响应"询问本板IP"的ARP请求)
// 帧布局: 0~5目的MAC | 6~11本板MAC | 12~13类型0x0806
//         14~15硬件类型 | 16~17协议类型 | 18硬件长度 | 19协议长度
//         20~21操作码(2=应答) | 22~27本板MAC | 28~31本板IP
//         32~37目标MAC | 38~41目标IP | 42~59填充0 | 60~63 FCS (总长64字节)
//
// 以太网最小帧长 64 字节(DA..FCS, 不含前导码); ARP 载荷仅 28 字节,
// 因此偏移 42~59 填充 0x00, FCS 置于 60~63, 总长 64 字节。
module arp_tx #(
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP  = 32'hC0A8_017B
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        reply_en,     // 来自arp_rx
    input  wire [31:0] req_ip,       // 请求者IP
    input  wire [47:0] req_mac,      // 请求者MAC
    output reg         req,
    input  wire        grant,
    output reg         done,
    output reg         tx_en,
    output wire [7:0]  tx_data
);

    localparam S_IDLE = 2'd0, S_WAIT = 2'd1, S_SEND = 2'd2;

    reg [1:0]  state;
    reg [47:0] rmac_r;
    reg [31:0] rip_r;
    reg [10:0] bcnt;

    // 发送字节选择: ARP头字段全部固定, 只有MAC/IP取自锁存值
    reg [7:0] byte_sel;
    wire [31:0] crc_fcs;

    always @(*) begin
        if (bcnt < 11'd6)
            byte_sel = rmac_r >> ((5 - bcnt[2:0]) * 8);   // 目的MAC=请求者
        else if (bcnt < 11'd12)
            byte_sel = BOARD_MAC >> ((11 - bcnt[3:0]) * 8);
        else 
        case (bcnt)
            11'd12: byte_sel = 8'h08;    // 以太网类型=ARP
            11'd13: byte_sel = 8'h06;
            11'd14: byte_sel = 8'h00;    // 硬件类型=以太网
            11'd15: byte_sel = 8'h01;
            11'd16: byte_sel = 8'h08;    // 协议类型=IPv4
            11'd17: byte_sel = 8'h00;
            11'd18: byte_sel = 8'h06;    // 硬件长度=6
            11'd19: byte_sel = 8'h04;    // 协议长度=4
            11'd20: byte_sel = 8'h00;    // 操作码=2(应答)
            11'd21: byte_sel = 8'h02;
            11'd22: byte_sel = BOARD_MAC[47:40];  // 发送方MAC=本板
            11'd23: byte_sel = BOARD_MAC[39:32];
            11'd24: byte_sel = BOARD_MAC[31:24];
            11'd25: byte_sel = BOARD_MAC[23:16];
            11'd26: byte_sel = BOARD_MAC[15:8];
            11'd27: byte_sel = BOARD_MAC[7:0];
            11'd28: byte_sel = BOARD_IP[31:24];   // 发送方IP=本板
            11'd29: byte_sel = BOARD_IP[23:16];
            11'd30: byte_sel = BOARD_IP[15:8];
            11'd31: byte_sel = BOARD_IP[7:0];
            11'd32: byte_sel = rmac_r[47:40];     // 目标MAC=请求者
            11'd33: byte_sel = rmac_r[39:32];
            11'd34: byte_sel = rmac_r[31:24];
            11'd35: byte_sel = rmac_r[23:16];
            11'd36: byte_sel = rmac_r[15:8];
            11'd37: byte_sel = rmac_r[7:0];
            11'd38: byte_sel = rip_r[31:24];      // 目标IP=请求者
            11'd39: byte_sel = rip_r[23:16];
            11'd40: byte_sel = rip_r[15:8];
            11'd41: byte_sel = rip_r[7:0];
            default:                              // 42~59 填充, 60~63 FCS
                if (bcnt < 11'd60)
                    byte_sel = 8'h00;             // 填充到最小帧长
                else
                    byte_sel = crc_fcs >> ((bcnt - 11'd60) * 8);
        endcase
    end

    assign tx_data = byte_sel;

    crc32_d8 u_crc32 (
        .clk(clk), .rst(rst),
        .data(tx_data),
        .data_en(tx_en && (bcnt < 11'd60)),  // CRC覆盖0~59(头+ARP+填充)
        .crc_out(crc_fcs), .crc_ok()
    );

    // 发送状态机
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; req <= 1'b0; done <= 1'b0;
            tx_en <= 1'b0; bcnt <= 11'd0;
            rmac_r <= 48'd0; rip_r <= 32'd0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (reply_en) begin
                        rmac_r <= req_mac;
                        rip_r  <= req_ip;
                        req    <= 1'b1;
                        state  <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (grant) begin
                        bcnt  <= 11'd0;
                        tx_en <= 1'b1;
                        state <= S_SEND;
                    end
                end
                S_SEND: begin
                    if (bcnt == 11'd63) begin    // 64字节发完
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
