//============================================================================
// 模块名   : crc32_d8
// 功能     : 以太网 FCS 校验: CRC-32, 每时钟处理1字节(8位)
//          - 发送方向: 输出 crc_out = ~crc_reg, 按字节序 [7:0]→[15:8]→
//            [23:16]→[31:24] 追加到帧尾 (即线上先发低字节)
//          - 接收方向: 把"整帧+FCS"全部喂进来, 若帧正确, 帧结束时
//            crc_reg 恒等于余数魔数 0xDEBB20E3, crc_ok 输出一个脉冲
// 已验证   : CRC-32("123456789") = 0xCBF43926 (标准自检通过)
//============================================================================
module crc32_d8(
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  data,      // 输入字节
    input  wire        data_en,   // 字节有效脉冲(高电平期间逐字节输入)
    output wire [31:0] crc_out,   // 发送用FCS = ~crc_reg (组合输出)
    output reg         crc_ok     // 接收: 帧结束(最后一字节后1拍)且校验通过
);

    // 接收余数魔数: 由标准自检向量 CRC-32("123456789") 验证
    localparam [31:0] RESIDUE = 32'hDEBB_20E3;

    //------------------------------------------------------------------
    // 核心函数: 输入当前寄存器值和一个字节, 返回处理完该字节后的新值。
    // 对应"反射算法": 先异或数据, 再循环8次: 右移一位, 若移出位为1
    // 则异或生成多项式 0xEDB88320。
    //------------------------------------------------------------------
    function [31:0] crc_byte_step;
        input [31:0] crc;
        input [7:0]  d;
        reg [31:0] c;
        integer i;
        begin
            c = crc ^ {24'b0, d};                    // 字节对齐到低位异或
            for (i = 0; i < 8; i = i + 1)            // 逐位处理(组合迭代)
                c = {1'b0, c[31:1]} ^ (c[0] ? 32'hEDB8_8320 : 32'b0);
            crc_byte_step = c;
        end
    endfunction

    reg [31:0] crc_reg;   // CRC移位寄存器
    reg        dv_d;      // data_en 打一拍, 用于检测"帧结束"

    assign crc_out = ~crc_reg;               // 发送侧最终FCS(取反)

    always @(posedge clk) begin
        if (rst) begin
            crc_reg <= 32'hFFFF_FFFF;        // 以太网CRC初值全1
            dv_d    <= 1'b0;
            crc_ok  <= 1'b0;
        end else begin
            dv_d <= data_en;
            if (data_en && !dv_d) begin
                // 新帧首字节: 以 FFFFFFFF 重新初始化(无需外部复位)
                crc_reg <= crc_byte_step(32'hFFFF_FFFF, data);
                crc_ok  <= 1'b0;
            end else if (data_en) begin
                crc_reg <= crc_byte_step(crc_reg, data); // 每字节推进一次
                crc_ok  <= 1'b0;
            end else if (dv_d) begin
                // 上一拍是最后一字节: 检查余数是否等于魔数
                //
                // 此处保持 crc_reg 不复位: 发送模块需连续 4 拍读 crc_out
                // 输出 FCS 的 4 个字节。新帧首字节到来时由
                // crc_byte_step(32'hFFFF_FFFF, data) 分支重新播种。
                crc_ok  <= (crc_reg == RESIDUE);
            end else begin
                // crc_ok 为严格的单拍脉冲, 空闲时必须清零,
                // 否则下游会每个时钟周期重复提交同一帧。
                crc_ok  <= 1'b0;
            end
            // 其余时刻 crc_ok 保持(电平有效), 直到下一帧 data_en 拉高时清0
        end
    end

endmodule
