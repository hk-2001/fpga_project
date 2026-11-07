`timescale 1ns / 1ps
//============================================================================
// tb_icmp_large : 大载荷 ICMP 回显测试（校验计数器位宽与 FIFO 回读）
//
// 被测   : rtl/icmp/icmp_rx.v（含 XPM 回显 FIFO）
//
// 为什么要有这个用例:
//   现有 tb_eth_top / tb_icmp 用的都是小包(ICMP 数据 8 字节), 根本压不到
//   小包压不到边界条件, 改对了也看不出来。本用例用一个 **200 字节**的大 Echo
//   请求, 直接命中这两项:
//
//   计数器位宽不足时: cnt 仅 6 位 -> cnt 卡在 63 后 hi_byte 冻结 -> 第 57 个载荷字节起
//       16 位字配对错乱 -> 校验和算错 -> reply_en 不产生(表现为"大包不通")。
//       修复后: cnt 为 11 位, 全程正确配对 -> reply_en 必须产生。
//
//   回显 FIFO 原深 1024。本例 200 字节不足以撑爆 1024, 但配合
//       `!fifo_full` 反压后可确认写入路径无损; 深度已改为 2048,
//       足以容纳 1500 MTU 下的 1472 字节最大回显数据。
//
// 测试点:
//   1) 200 字节数据的大 Echo 请求必须产生 reply_en(计数器位宽的关键判据)
//   2) data_len 必须等于 200
//   3) FIFO 读回的 200 字节必须与输入逐字节一致(证明数据路径无损)
//
// 注: ICMP 校验和在 testbench 内用反码求和算出, 不写死常数, 便于改 DLEN 复测。
//============================================================================
module tb_icmp_large;

    reg clk = 0;
    reg rst = 1;
    always #4 clk = ~clk;                 // 125MHz

    // 直接驱动 icmp_rx 的载荷接口(绕过 mac_rx/ip_rx, 聚焦本模块)
    reg        p_sof = 0;
    reg        p_en  = 0;
    reg [7:0]  p_data = 0;
    reg [15:0] payload_len = 0;
    reg        ip_ok = 0;
    wire       reply_en;
    wire [15:0] id, seq, icmp_cksum, data_len;

    reg        fifo_rd = 0;
    wire [7:0] fifo_dout;
    wire       fifo_empty;

    icmp_rx dut (
        .clk(clk), .rst(rst),
        .p_sof(p_sof), .p_en(p_en), .p_eof(1'b0),
        .p_data(p_data), .payload_len(payload_len), .ip_ok(ip_ok),
        .reply_en(reply_en), .id(id), .seq(seq),
        .icmp_cksum(icmp_cksum), .data_len(data_len),
        .fifo_rd(fifo_rd), .fifo_dout(fifo_dout), .fifo_empty(fifo_empty)
    );

    //---------------- 构造 ICMP Echo 请求 ----------------
    parameter DLEN  = 200;                // 数据字节数(>56, 覆盖计数器位宽边界)
    parameter TOTAL = 8 + DLEN;           // ICMP 报文总长

    reg [7:0] msg [0:511];
    reg [31:0] sum;
    reg [15:0] ck;
    integer i, k, errors;
    reg [7:0] rd;
    integer wait_cnt;

    // 反码求和计算 ICMP 校验和(覆盖整个 ICMP 报文)
    task calc_cksum;
        integer j;
        begin
            sum = 32'd0;
            for (j = 0; j < TOTAL; j = j + 2) begin
                if (j + 1 < TOTAL) sum = sum + {msg[j], msg[j+1]};
                else               sum = sum + {msg[j], 8'h00};
            end
            // 进位回卷(最多两次)
            while (sum[31:16] != 16'd0)
                sum = {16'h0, sum[31:16]} + {16'h0, sum[15:0]};
            ck = ~sum[15:0];
        end
    endtask

    // 以 p_sof/p_en 时序把整个 ICMP 报文喂进去
    task push_msg;
        integer j;
        begin
            // 首字节: p_sof 与数据同拍
            @(negedge clk);
            p_data <= msg[0]; p_sof <= 1'b1; p_en <= 1'b1;
            @(negedge clk);
            p_sof <= 1'b0;
            for (j = 1; j < TOTAL; j = j + 1) begin
                p_data <= msg[j];
                @(negedge clk);
            end
            p_en <= 1'b0; p_data <= 8'h00;
            // 帧尾: 给出 ip_ok 单拍脉冲(模拟 ip_rx 提交)
            @(negedge clk);
            ip_ok <= 1'b1;
            @(negedge clk);
            ip_ok <= 1'b0;
        end
    endtask

    initial begin
        errors = 0;

        // 1) 填充 ICMP 报文: type=8(Echo请求) code=0 id=0001 seq=0001 + 200字节数据
        msg[0] = 8'h08;  msg[1] = 8'h00;
        msg[2] = 8'h00;  msg[3] = 8'h00;     // 校验和先置0再回填
        msg[4] = 8'h00;  msg[5] = 8'h01;     // id
        msg[6] = 8'h00;  msg[7] = 8'h01;     // seq
        for (i = 0; i < DLEN; i = i + 1)
            msg[8+i] = i[7:0];               // 数据图案 0,1,2,...

        // 2) 算校验和并回填
        calc_cksum;
        msg[2] = ck[15:8];
        msg[3] = ck[7:0];
        $display("  ICMP 报文: 总长 %0d 字节(数据 %0d), 校验和=%h", TOTAL, DLEN, ck);

        // 3) 复位释放
        rst = 1; #100; rst = 0; #100;
        payload_len = TOTAL;

        // 4) 喂入报文
        push_msg;

        // 5) 等 reply_en(计数器位宽不足时这里会等不到)
        wait_cnt = 0;
        while (reply_en !== 1'b1 && wait_cnt < 500) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end

        if (reply_en !== 1'b1) begin
            errors = errors + 1;
            $display("  [BIG] FAIL: %0d 字节大包未产生 reply_en(cnt 位宽问题未修复?)", DLEN);
        end else
            $display("  [BIG] OK  : %0d 字节大包正常产生 reply_en", DLEN);

        if (data_len !== DLEN) begin
            errors = errors + 1;
            $display("  [长度] FAIL: data_len=%0d, 期望 %0d", data_len, DLEN);
        end else
            $display("  [长度] OK  : data_len=%0d", data_len);

        // 6) 从回显 FIFO 读回全部数据, 逐字节比对(数据路径无损)
        for (k = 0; k < DLEN; k = k + 1) begin
            @(posedge clk); #1;
            rd = fifo_dout;
            if (rd !== msg[8+k]) begin
                errors = errors + 1;
                $display("  [FIFO] FAIL: 第%0d字节=%h, 期望%h", k, rd, msg[8+k]);
            end
            @(negedge clk); fifo_rd <= 1'b1;
            @(posedge clk); #1;
            @(negedge clk); fifo_rd <= 1'b0;
        end
        $display("  [FIFO] 回读 %0d 字节完成", DLEN);

        #100;
        if (errors == 0) $display("==== tb_icmp_large: PASS ====");
        else             $display("==== tb_icmp_large: %0d 个错误 FAIL ====", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("==== tb_icmp_large: 超时 FAIL ====");
        $finish;
    end

endmodule
