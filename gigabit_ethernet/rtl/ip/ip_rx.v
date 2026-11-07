//============================================================================
// 模块名   : ip_rx
// 功能     : IP层接收: 解析IPv4包头, 校验IP首部校验和与目的IP,
//            把载荷(ICMP/UDP报文)作为字节流送往下游
// 报文结构 : 帧内偏移
//            14 版本|首部长度(0x45) | 15 服务类型 | 16~17 总长度
//            18~19 标识 | 20~21 标志|片偏移 | 22 生存时间TTL
//            23 协议(1=ICMP, 17=UDP) | 24~25 首部校验和
//            26~29 源IP | 30~33 目的IP | 34~ 载荷
// 校验和   : 首部按16位字反码求和, 结果须为0xFFFF(含校验和字段本身)
// 载荷输出 : p_en 只在 [34, 13+总长度] 区间有效, 自动剔除MAC头和帧尾FCS
// 计数说明 : sof与帧首字节对齐; sof当拍cnt清, 下一字节为偏移1
//
// cnt 用 11 位(可计到 1517, 覆盖最大帧 1518), pkt_last 取完整 total_len,
// 所有比较同宽, 保证长帧也能正确产生 p_eof。
//============================================================================
module ip_rx #(
    parameter [31:0] BOARD_IP = 32'hC0A8_017B
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sof,
    input  wire        en,
    input  wire [7:0]  data,
    input  wire [15:0] eth_type,
    input  wire        crc_ok,
    output reg         p_sof,        // 载荷首字节脉冲(与p_data对齐)
    output reg  [7:0]  p_data,
    output reg         p_en,
    output reg         p_eof,        // 载荷末字节脉冲
    output reg  [15:0] payload_len,  // 载荷长度 = IP总长度-20
    output reg  [7:0]  protocol,
    output reg  [31:0] src_ip,
    output reg         ip_ok         // 帧尾提交: CRC+校验和+目的IP全对
);
    // cnt 必须能计到最大帧偏移(1518字节帧 -> 最大偏移1517), 故用11位
    reg [10:0] cnt;
    reg [15:0] total_len;
    reg [7:0]  ver_ihl;
    reg [31:0] dst_ip_r;
    reg [31:0] acc;            // 首部校验和累加器
    reg [7:0]  hi_byte;        // 16位字的高字节暂存
    reg        hdr_ck_ok;
    reg        dst_ok;
    reg        parsed;

    wire is_ip = (eth_type == 16'h0800);

    // 载荷区间: 帧偏移34 ~ (13+total_len); FCS在其后, 自动被排除
    // 最后一个载荷字节偏移 = 14(MAC头) + total_len(IP总长) - 1 = 13 + total_len
    wire [10:0] pkt_last   = 11'd13 + total_len;
    wire        in_payload = is_ip && (cnt >= 11'd34) && (cnt <= pkt_last);

    // 反码求和折叠: 32位 -> 16位(进位回卷两次)
    wire [16:0] fold1 = acc[31:16] + acc[15:0];
    wire [16:0] fold2 = {1'b0, fold1[15:0]} + {16'd0, fold1[16]};

    always @(posedge clk) begin
        if (rst) begin
            cnt <= 11'd0;      total_len <= 16'd0;
            ver_ihl <= 8'd0;   dst_ip_r <= 32'd0;
            acc <= 32'd0;      hi_byte <= 8'd0;
            hdr_ck_ok <= 1'b0; dst_ok <= 1'b0;
            parsed <= 1'b0;
            p_sof <= 1'b0;  p_en <= 1'b0;  p_eof <= 1'b0;  ip_ok <= 1'b0;
            p_data <= 8'd0; payload_len <= 16'd0;
            protocol <= 8'd0;  src_ip <= 32'd0;
        end else begin
            p_sof <= 1'b0;             // 以下均为默认单拍脉冲
            p_en  <= 1'b0;
            p_eof <= 1'b0;
            ip_ok <= 1'b0;

            if (en) begin
                // 1) 载荷透传(sof当拍cnt为旧值, 必须屏蔽)
                if (in_payload && !sof) begin
                    p_data <= data;
                    p_en   <= 1'b1;
                    if (cnt == 11'd34)
                        p_sof <= 1'b1;
                    if (cnt == pkt_last)
                        p_eof <= 1'b1;
                end
                // 2) 逐字段解析
                case (cnt)
                    11'd14: ver_ihl <= data;
                    11'd16: total_len[15:8] <= data;
                    11'd17: total_len[7:0]  <= data;
                    11'd23: protocol <= data;
                    // 网络字节序为大端: 先收到的字节必须放在最高字节
                    11'd26, 11'd27, 11'd28, 11'd29:
                        src_ip[(29-cnt)*8 +: 8] <= data;
                    11'd30, 11'd31, 11'd32, 11'd33:
                        dst_ip_r[(33-cnt)*8 +: 8] <= data;
                    default: ;
                endcase
                // 3) 首部校验和累加(偏移14~33, 共10个16位字)
                //
                    // 首部校验和累加器在 sof 时按帧清零, 且只累加 IPv4 帧,
                    // 避免跨帧累加以及 ARP 帧字节混入。
                if (sof) begin
                    acc     <= 32'd0;
                    hi_byte <= 8'd0;
                end else if (is_ip && cnt >= 11'd14 && cnt <= 11'd33) begin
                    if (cnt[0] == 1'b0)          // 偶偏移: 高字节
                        hi_byte <= data;
                    else                          // 奇偏移: 拼字累加
                        acc <= acc + {8'd0, hi_byte, data};
                end
                // 4) 偏移18: 总长度已齐, 算出载荷长度
                if (cnt == 11'd18 && !sof)
                    payload_len <= total_len - 16'd20;
                // 5) 偏移34: 累加完毕, 反码折叠判结果
                if (cnt == 11'd34 && !sof) begin
                    hdr_ck_ok <= (fold2[15:0] == 16'hFFFF);
                    dst_ok    <= (dst_ip_r == BOARD_IP);
                    parsed    <= 1'b1;
                end
                // 6) 字节计数(sof当拍计0, 下一字节为偏移1)
                if (sof)
                    cnt <= 11'd1;
                else if (cnt < 11'd1517)          // 覆盖最大帧1518字节
                    cnt <= cnt + 11'd1;
            end else if (crc_ok) begin
                // 帧尾提交: 所有条件同时成立才放行本IP包
                ip_ok <= is_ip && parsed && hdr_ck_ok && dst_ok
                         && (ver_ihl == 8'h45) && (total_len >= 16'd20);
            end
        end
    end

endmodule
