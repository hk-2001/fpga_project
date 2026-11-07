// tx_arbiter: 发送仲裁, 固定优先级 ARP > ICMP > UDP, done后释放

module tx_arbiter(
    input  wire       clk,
    input  wire       rst,
    input  wire       arp_req,   input  wire arp_done,
    input  wire [7:0] arp_data,  input  wire arp_en,
    input  wire       icmp_req,  input  wire icmp_done,
    input  wire [7:0] icmp_data, input  wire icmp_en,
    input  wire       udp_req,   input  wire udp_done,
    input  wire [7:0] udp_data,  input  wire udp_en,
    output reg        arp_gnt,
    output reg        icmp_gnt,
    output reg        udp_gnt,
    output reg  [7:0] tx_data,
    output reg        tx_en
);

    localparam OWNER_NONE = 2'd0, OWNER_ARP = 2'd1,
               OWNER_ICMP = 2'd2, OWNER_UDP = 2'd3;

    //----------------------------------------------------------------------
    // 帧间隔(IFG)强制空闲
    //   802.3 要求相邻帧之间至少 12 拍线路空闲(125MHz 下 12 字节 = 96ns)。
    //   下游 preamble_inserter 含 9 级延迟线, 帧结束后还需 8 拍才能把尾部
    //   (含 FCS)完全移出; 在这 8 拍内发起新帧会覆盖尚未输出的尾部。
    //   因此 arb_tx_en 拉低 G 拍后才允许授权下一帧, 线上空闲 = G - 8。
    //   取 G = 20: 8 拍用于冲刷尾部, 余 12 拍满足 IFG。
    //----------------------------------------------------------------------
    localparam [4:0] IFG_HOLD = 5'd20;

    reg [1:0] owner;
    reg [4:0] gap_cnt;        // 帧间隔倒计时(非0 = 处于强制空闲期)

    // 总线占用状态: 空闲时按优先级响应请求, 占用期间等到done释放
    always @(posedge clk) begin
        if (rst) begin
            owner   <= OWNER_NONE;
            gap_cnt <= 5'd0;
        end else begin
            // 帧间隔倒计时(每拍递减, 到0即允许下一次授权)
            if (gap_cnt != 5'd0)
                gap_cnt <= gap_cnt - 5'd1;

            case (owner)
                OWNER_NONE: begin
                    // 只有间隔满足才能授权, 否则继续等待
                    if (gap_cnt == 5'd0) begin
                        if      (arp_req)  owner <= OWNER_ARP;
                        else if (icmp_req) owner <= OWNER_ICMP;
                        else if (udp_req)  owner <= OWNER_UDP;
                    end
                end
                OWNER_ARP:  if (arp_done)  begin owner <= OWNER_NONE; gap_cnt <= IFG_HOLD; end
                OWNER_ICMP: if (icmp_done) begin owner <= OWNER_NONE; gap_cnt <= IFG_HOLD; end
                OWNER_UDP:  if (udp_done)  begin owner <= OWNER_NONE; gap_cnt <= IFG_HOLD; end
                default: owner <= OWNER_NONE;
            endcase
        end
    end

    // 授权信号(组合输出)与数据汇聚(多路选择)
    always @(*) begin
        arp_gnt  = (owner == OWNER_ARP);
        icmp_gnt = (owner == OWNER_ICMP);
        udp_gnt  = (owner == OWNER_UDP);
        case (owner)
            OWNER_ARP:  begin tx_data = arp_data;  tx_en = arp_en;  end
            OWNER_ICMP: begin tx_data = icmp_data; tx_en = icmp_en; end
            OWNER_UDP:  begin tx_data = udp_data;  tx_en = udp_en;  end
            default:    begin tx_data = 8'h00;     tx_en = 1'b0;    end
        endcase
    end

endmodule
