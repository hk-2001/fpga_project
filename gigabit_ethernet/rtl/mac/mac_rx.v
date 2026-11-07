//============================================================================
// 创造者： HUKUAN
// 模块名   : mac_rx
// 功能     : MAC层接收: 帧定界(SFD检测) + MAC头提取 + CRC32校验
// 时序说明 : 内部有一拍流水线, sof/data/en 三者严格对齐:
//            sof=1 的那一拍, data上正是帧的第0字节(目的MAC首字节)
//============================================================================
module mac_rx(
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  gmii_d,
    input  wire        gmii_dv,
    input  wire        gmii_rx_er,   // GMII接收错误(由 rgmii_to_gmii 恢复)
    output reg         sof,          // 帧首字节脉冲(与data对齐)
    output reg  [7:0]  data,         // 帧字节流(含FCS)
    output reg         en,           // 字节有效
    output reg         eof,          // 帧尾脉冲(dv拉低后1拍)
    output reg  [47:0] dst_mac,
    output reg  [47:0] src_mac,
    output reg  [15:0] eth_type,
    output wire        crc_ok        // FCS校验通过(eof后1拍)
);

    reg       in_frame;
    reg [5:0] cnt;
    reg       er_hit;     // 当前帧出现过 RX_ER(整帧损坏标志)

    wire frame = gmii_dv && in_frame;

    always @(posedge clk) begin
        if (rst) begin
            in_frame <= 1'b0;  cnt <= 6'd0; er_hit <= 1'b0;
            sof <= 1'b0; en <= 1'b0; eof <= 1'b0; data <= 8'd0;
            dst_mac <= 48'd0; src_mac <= 48'd0; eth_type <= 16'd0;
        end else begin
            //--------------------------------------------------
            // 一拍流水线: 让sof与第0字节对齐输出
            //--------------------------------------------------
            data <= gmii_d;
            en   <= frame;
            sof  <= frame && (cnt == 6'd0);
            eof  <= in_frame && !gmii_dv;

            //--------------------------------------------------
            // 帧定界: 检测到SFD(0xD5)后, 下一字节即目的MAC首字节
            //--------------------------------------------------
            if (!in_frame) begin
                if (gmii_dv && gmii_d == 8'hD5) begin
                    in_frame <= 1'b1;
                    cnt      <= 6'd0;
                    er_hit   <= 1'b0;   // 新帧开始, 清上一帧错误标记(crc_ok已用过)
                    dst_mac  <= 48'd0; src_mac <= 48'd0; eth_type <= 16'd0;
                end
            end else if (gmii_dv) begin
                if (gmii_rx_er) er_hit <= 1'b1;   // 帧内 PHY 报错误符号, 整帧标记损坏
                case (cnt)
                    6'd0, 6'd1, 6'd2, 6'd3, 6'd4, 6'd5:
                        // 每拍左移拼接: 首字节最终落在最高字节(避免反序)
                        dst_mac <= {dst_mac[39:0], gmii_d};
                    6'd6, 6'd7, 6'd8, 6'd9, 6'd10, 6'd11:
                        src_mac <= {src_mac[39:0], gmii_d};
                    6'd12: eth_type[15:8] <= gmii_d;
                    6'd13: eth_type[7:0]  <= gmii_d;
                    default: ;
                endcase
                if (cnt < 6'd63)
                    cnt <= cnt + 6'd1;
            end else begin
                in_frame <= 1'b0;      // 帧结束, 等待下一个SFD
            end
        end
    end

    // CRC32: 校验范围=整帧(目的MAC起, 含FCS)
    wire [31:0] crc_fcs;
    wire        crc_ok_raw;
    crc32_d8 u_crc32 (
        .clk     (clk),
        .rst     (rst),
        .data    (data),
        .data_en (en),
        .crc_out (crc_fcs),
        .crc_ok  (crc_ok_raw)
    );
    // 标准 CRC 之外叠加 GMII RX_ER: 任一字节期间 PHY 报错误, 整帧判失败
    assign crc_ok = crc_ok_raw && !er_hit;

endmodule
