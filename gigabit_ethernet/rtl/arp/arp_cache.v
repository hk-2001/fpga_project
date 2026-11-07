//============================================================================
// 模块名   : arp_cache
// 功能     : ARP缓存: 存储学习到的 IP->MAC 映射(单条目简化版)
// 说明     : 图中架构的"ARP cache"。真实系统常用多条目哈希/CAM表,
//            扩展为多条目时把单寄存器换成RAM数组+索引即可。
//============================================================================
module arp_cache(
    input  wire        clk,
    input  wire        rst,
    // 写端口(学习): 来自arp_rx
    input  wire        wr_en,
    input  wire [31:0] wr_ip,
    input  wire [47:0] wr_mac,
    // 查询端口: 供将来板卡主动发包时解析对端MAC使用
    input  wire        query_en,
    input  wire [31:0] query_ip,
    output reg         hit,          // 命中标志(查询后1拍有效)
    output reg  [47:0] mac_out       // 命中时的MAC
);

    reg [31:0] cache_ip;
    reg [47:0] cache_mac;
    reg        valid;                // 表项是否有效

    always @(posedge clk) begin
        if (rst) begin
            valid   <= 1'b0;
            hit     <= 1'b0;
            mac_out <= 48'd0;
        end else begin
            // 学习: 同一IP刷新MAC, 新IP覆盖旧表项(单条目策略)
            if (wr_en) begin
                cache_ip <= wr_ip;
                cache_mac<= wr_mac;
                valid    <= 1'b1;
            end
            // 查询: 打一拍输出, 便于时序收敛
            hit <= 1'b0;
            if (query_en && valid && (query_ip == cache_ip)) begin
                hit     <= 1'b1;
                mac_out <= cache_mac;
            end
        end
    end

endmodule
