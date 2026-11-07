//============================================================================
// 模块名   : arp_rx
// 功能     : ARP报文接收解析: 提取操作码/发送方MAC+IP/目标IP,
//          1) 更新ARP缓存(学习对端的 IP->MAC 映射)
//          2) 若是"询问本板IP"的ARP请求, 通知arp_tx发送ARP应答
// 报文结构 : 帧内偏移(从目的MAC第1字节算起)
//            0~5 目的MAC | 6~11 源MAC | 12~13 类型0x0806
//            14~15 硬件类型 | 16~17 协议类型 | 18 硬件长度 | 19 协议长度
//            20~21 操作码(1请求/2应答) | 22~27 发送方MAC(sha)
//            28~31 发送方IP(spa) | 32~37 目标MAC(tha) | 38~41 目标IP(tpa)
//============================================================================
module arp_rx #(
    parameter [31:0] BOARD_IP = 32'hC0A8_017B      // 本板IP 192.168.1.123
)(
    input  wire        clk,
    input  wire        rst,
    // 来自mac_rx的帧字节流
    input  wire        sof,
    input  wire        en,
    input  wire [7:0]  data,
    input  wire [15:0] eth_type,
    input  wire        crc_ok,       // 帧尾FCS校验通过脉冲
    // ARP缓存更新接口(接arp_cache写口)
    output reg         update_en,    // 学习到新的IP->MAC映射
    output reg  [31:0] update_ip,
    output reg  [47:0] update_mac,
    // ARP应答请求(接arp_tx)
    output reg         reply_en,     // 请求发送ARP应答
    output reg  [31:0] req_ip,       // 请求者IP(应答的目的IP)
    output reg  [47:0] req_mac       // 请求者MAC(应答的目的MAC)
);

    reg [5:0]  cnt;
    reg [15:0] oper_r;      // 操作码
    reg [47:0] sha_r;       // 发送方MAC
    reg [31:0] spa_r;       // 发送方IP
    reg [31:0] tpa_r;       // 目标IP
    reg        parsed;      // 已完整解析出42字节

    wire is_arp = (eth_type == 16'h0806);

    always @(posedge clk) begin
        if (rst) begin
            cnt       <= 6'd0;
            oper_r    <= 16'd0;
            sha_r     <= 48'd0;
            spa_r     <= 32'd0;
            tpa_r     <= 32'd0;
            parsed    <= 1'b0;
            update_en <= 1'b0;
            reply_en  <= 1'b0;
        end else begin
            update_en <= 1'b0;      // 默认单拍脉冲
            reply_en  <= 1'b0;

            if (en) begin
                case (cnt)
                    6'd20: oper_r[15:8] <= data;
                    6'd21: oper_r[7:0]  <= data;
                    // 网络字节序为大端: 先收到的字节必须放在最高字节
                    6'd22, 6'd23, 6'd24, 6'd25, 6'd26, 6'd27:
                        sha_r[(27-cnt)*8 +: 8] <= data;
                    // 网络字节序为大端: 先收到的字节必须放在最高字节
                    6'd28, 6'd29, 6'd30, 6'd31:
                        spa_r[(31-cnt)*8 +: 8] <= data;
                    6'd38, 6'd39, 6'd40, 6'd41:
                        tpa_r[(41-cnt)*8 +: 8] <= data;
                    default: ;
                endcase
                if (cnt == 6'd41 && !sof)
                    parsed <= 1'b1;          // ARP定长28字节, 解析完毕
                if (sof) begin               // 帧首字节: 下一字节为偏移1
                    cnt    <= 6'd1;
                    parsed <= 1'b0;
                end else if (cnt < 6'd63) begin
                    cnt <= cnt + 6'd1;
                end
            end else if (crc_ok && is_arp && parsed) begin
                // 帧尾提交: CRC正确且确为ARP帧才生效
                // 1) 学习: 请求/应答都携带发送方MAC+IP, 都可入缓存
                if (spa_r != 32'd0) begin
                    update_en  <= 1'b1;
                    update_ip  <= spa_r;
                    update_mac <= sha_r;
                end
                // 2) 应答: 是ARP请求且询问的是本板IP -> 回应答
                if (oper_r == 16'd1 && tpa_r == BOARD_IP) begin
                    reply_en <= 1'b1;
                    req_ip   <= spa_r;
                    req_mac  <= sha_r;
                end
            end
        end
    end

endmodule
