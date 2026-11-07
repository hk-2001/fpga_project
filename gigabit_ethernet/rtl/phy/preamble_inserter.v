//============================================================================
// 模块名   : preamble_inserter
// 所处位置 : tx_arbiter 输出  ->  [本模块]  ->  gmii_to_rgmii 输入
//            (即"发送路径的最末一跳", 属于 GMII/PHY 接口层)
//
// 功能     : 给每一个待发的以太网帧前面补上前导码(Preamble)与帧起始定界符(SFD),
//            使最终送到 PHY 的字节流满足 IEEE 802.3 的帧格式要求。
//

//
// 帧格式  (IEEE 802.3, 发送时 MAC 必须负责产生前 8 字节):
//    [0]     ~ [6]     : 前导码 Preamble = 8'h55 x 7  (供对端做时钟同步/位同步)
//    [7]              : 帧起始定界符 SFD  = 8'hD5
//    [8]     ~ ...    : 目的MAC(6) 源MAC(6) 类型(2) 载荷 ... FCS(4)
//   注意: 以太网最小帧长 64 字节、CRC 校验范围都 **不包含** 前导码和 SFD,
//         它们不属于 MAC 帧本体。
//
// 实现原理 : 8 拍前导码 + 9 级延迟线
//   1) 检测到 s_en 上升沿(新帧开始)后, 连续 8 拍输出前导码与 SFD;
//   2) 并行把输入字节流打进 9 级流水线, 整体延后 9 拍;
//   3) 第 8 拍发完时延迟线刚好吐出第 0 个数据字节, 无缝衔接。
//   延迟线级数 = 8(前导码拍数) + 1(s_en 上升沿检测开销) = 9。
//============================================================================
module preamble_inserter(
    input  wire       clk,
    input  wire       rst,        // 高有效同步复位
    // 从设备侧(GMII): 帧从"目的MAC"第一字节开始, 不含前导码
    input  wire [7:0] s_data,
    input  wire       s_en,
    // 到 PHY 侧(GMII->RGMII): 已补齐 前导码+SFD
    output wire [7:0] m_data,
    output wire       m_en
);

    //------------------------------------------------------------------
    // 1) 帧起始检测: 抓住 s_en 的上升沿
    //    s_en_rise 是组合信号, 在 s_en 变高的"当拍"即为 1,
    //    这样下一拍状态机就能启动, 不会额外拖延。
    //------------------------------------------------------------------
    reg s_en_d;
    always @(posedge clk) begin
        if (rst) s_en_d <= 1'b0;
        else     s_en_d <= s_en;
    end
    wire s_en_rise = s_en & ~s_en_d;

    //------------------------------------------------------------------
    // 2) 9 级延迟线: 数据与使能各延后 9 拍
    //    dly_en 用移位寄存器实现, 其第 8 级即"延迟了 9 拍的 s_en",
    //    正好用来驱动后续数据的输出有效信号。
    //------------------------------------------------------------------
    reg [7:0] dly_data [0:8];
    reg [8:0] dly_en;

    always @(posedge clk) begin
        if (rst) begin
            dly_en <= 9'd0;
        end else begin
            // 使能: 每拍整体左移一位, 新采到的 s_en 补到最低位
            dly_en <= {dly_en[7:0], s_en};
            // 数据: 9 级流水, dly_data[0] 接输入, 逐级往下传
            dly_data[0] <= s_data;
            dly_data[1] <= dly_data[0];
            dly_data[2] <= dly_data[1];
            dly_data[3] <= dly_data[2];
            dly_data[4] <= dly_data[3];
            dly_data[5] <= dly_data[4];
            dly_data[6] <= dly_data[5];
            dly_data[7] <= dly_data[6];
            dly_data[8] <= dly_data[7];
        end
    end

    //------------------------------------------------------------------
    // 3) 前导码节拍状态机: s_en 上升沿后连续占 8 拍输出 {0x55 x7, 0xD5}
    //    pcnt: 0~6 -> 0x55(共7个), 7 -> 0xD5(SFD)
    //------------------------------------------------------------------
    reg [3:0] pcnt;
    reg       p_act;              // 1 = 当前拍正在输出前导码/SFD

    always @(posedge clk) begin
        if (rst) begin
            p_act <= 1'b0;
            pcnt  <= 4'd0;
        end else if (s_en_rise) begin
            p_act <= 1'b1;        // 新帧到来, 启动前导码
            pcnt  <= 4'd0;
        end else if (p_act) begin
            if (pcnt == 4'd7) begin
                p_act <= 1'b0;    // 已发完第 8 个(SFD), 交还给数据通路
                pcnt  <= 4'd0;
            end else begin
                pcnt  <= pcnt + 4'd1;
            end
        end
    end

    //------------------------------------------------------------------
    // 4) 输出选择
    //    输出采用 assign 组合逻辑, 保证 p_act/pcnt 更新当拍立即生效。
    //    若改为寄存器输出会多延迟一拍, 首字节前出现空拍导致帧错位。
    //    下游 gmii_to_rgmii 内含一级寄存, 组合输出不会引入时序问题。
    //------------------------------------------------------------------
    assign m_en   = p_act | dly_en[8];                      // 前导码期 + 数据期
    assign m_data = p_act ? (pcnt == 4'd7 ? 8'hD5 : 8'h55)  // 前导码 / SFD
                          : dly_data[8];                    // 延迟后的帧数据

endmodule
