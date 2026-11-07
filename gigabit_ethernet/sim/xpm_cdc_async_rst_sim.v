//============================================================================
// 模块名   : xpm_cdc_async_rst (仿真行为模型)
// 功能     : 与 Vivado XPM 宏 xpm_cdc_async_rst 行为对齐的仿真替身。
//            - 异步断言: src_arst 按 RST_ACTIVE_HIGH 判定, 立即生效(与 dest_clk 异步)
//            - 同步释放: dest_clk 打 DEST_SYNC_FF 拍后释放
// 说明     : 仅用于 iverilog 等第三方仿真器; Vivado 综合/仿真时请使用原生 XPM。
//============================================================================
module xpm_cdc_async_rst #(
    parameter integer DEST_SYNC_FF    = 4,
    parameter integer INIT_SYNC_FF    = 0,
    parameter integer RST_ACTIVE_HIGH = 1
)(
    input  wire src_arst,   // 异步复位输入
    input  wire dest_clk,   // 目的时钟
    output wire dest_arst   // 同步后的复位输出(极性由 RST_ACTIVE_HIGH 决定)
);
    reg [DEST_SYNC_FF-1:0] sync_ff;
    // 内部统一为高有效断言: RST_ACTIVE_HIGH=1 时 src_arst 高=断言; =0 时 src_arst 低=断言
    wire arst = RST_ACTIVE_HIGH ? src_arst : ~src_arst;

    always @(posedge dest_clk or posedge arst) begin
        if (arst)
            sync_ff <= {DEST_SYNC_FF{1'b1}};
        else
            sync_ff <= {1'b0, sync_ff[DEST_SYNC_FF-1:1]};
    end

    // 输出极性跟随 RST_ACTIVE_HIGH: 高有效时断言=1, 低有效时断言=0
    assign dest_arst = RST_ACTIVE_HIGH ? (|sync_ff) : (~|sync_ff);
endmodule
