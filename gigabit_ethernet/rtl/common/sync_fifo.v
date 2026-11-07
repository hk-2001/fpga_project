//============================================================================
// 模块名   : sync_fifo
// 功能     : 通用同步FIFO(首字直通 FWFT), 用于ICMP数据缓存 / UDP接收缓存
// 说明     : 纯RTL实现, 不依赖Vivado FIFO IP, 便于仿真与移植;
//            若使用Vivado "FIFO Generator"可替换, 行为需配置为FWFT(First
//            Word Fall Through)模式。
// 实现     : 双指针环形缓冲 / 空满判断 / FWFT 读 / $clog2 位宽计算
//============================================================================
module sync_fifo #(
    parameter DATA_W = 8,                    // 数据位宽
    parameter DEPTH  = 1024,                 // 深度(必须是2的幂)
    // AW 在参数列表中声明(端口 output [AW:0] count 会引用它),
    // 以便 iverilog 等工具解析端口时能绑定该参数。
    parameter AW     = $clog2(DEPTH)         // 地址位宽: DEPTH=1024 -> 10
)(
    input  wire              clk,            // 时钟
    input  wire              rst,            // 同步高有效复位
    input  wire              clr,            // 清空(丢弃当前缓存内容)
    // 写端口
    input  wire              wr_en,          // 写使能(满时写入被忽略)
    input  wire [DATA_W-1:0] din,            // 写数据
    // 读端口 (FWFT: dout 上始终是队首数据, rd_en=1 表示"取走"它)
    input  wire              rd_en,          // 读使能
    output wire [DATA_W-1:0] dout,           // 队首数据(组合输出)
    // 状态
    output wire              full,           // 满标志
    output wire              empty,          // 空标志
    output wire [AW:0]       count           // 当前数据个数
);

    // 存储体: 分布式RAM(RAM64M/LUTRAM), 深度大时Vivado会自动换成BRAM
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // 读/写指针: 多用1位作为"回绕标志"用于区分空/满
    reg [AW:0] wptr;
    reg [AW:0] rptr;

    assign full  = (wptr[AW] != rptr[AW]) && (wptr[AW-1:0] == rptr[AW-1:0]);
    assign empty = (wptr == rptr);
    assign count = wptr - rptr;              // 无符号减法, 天然正确

    // FWFT: 组合读, dout 始终等于队首数据
    assign dout = mem[rptr[AW-1:0]];

    // 写逻辑
    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wptr[AW-1:0]] <= din;
    end

    // 指针逻辑 + 清空(用于丢弃错误报文)
    always @(posedge clk) begin
        if (rst || clr) begin
            wptr <= {(AW+1){1'b0}};
            rptr <= {(AW+1){1'b0}};
        end else begin
            if (wr_en && !full)
                wptr <= wptr + 1'b1;
            if (rd_en && !empty)
                rptr <= rptr + 1'b1;
        end
    end

endmodule
