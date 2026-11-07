`timescale 1ns / 1ps
//============================================================================
// tb_eth_top : 全工程系统级仿真(模拟PHY + 三种帧 + 应答校验)
//
// 被测     : rtl/top/eth_top.v (完整协议栈 + RGMII 收发)
// 依赖     : sim/xilinx_prims_sim.v (IDDR/ODDR/BUFG/MMCME2_BASE 行为模型)
//            sim/xpm_fifo_sync_sim.v (XPM FIFO 行为模型)
//
// 激励方式 : 完全模拟 PHY —— 用 RGMII DDR 时序把字节送给 FPGA
//            (上升沿=低4位, 下降沿=高4位), 并额外把 RXC 推后2ns以建模
//            PHY 内部延迟(RGMII-ID), 再按同样规则回收 FPGA 发出的字节
//
// 测试点(说明写在注释里, 不再逐条打印):
//   1) ARP  : 收到询问本板IP的ARP请求 -> 回应答, 长度必须为 64(最小帧长)
//             操作码=2, 发送方IP=本板IP, 填充区(42~59)为0
//   2) ICMP : 收到 Echo 请求 -> 回 54 字节应答, 类型=0, 数据"abcdefgh"原样回显
//   3) UDP  : 收到端口5000的报文 -> 回 50 字节回显, 目的端口=12345, 数据"PING"回显
//   4) 前导码: 每一帧最前面必须是 7字节0x55 + 1字节0xD5(由顶层新增的
//             rtl/phy/preamble_inserter.v 插入), 且之后才是目的MAC
//
// ARP 应答按 64 字节校验(最小帧长), 与 arp_tx 一致。
//           同时补接 phy_rst_n 端口, 并等待 PLL 锁定后再发帧。
//
// 【重要修改】发送路径新增前导码/SFD 插入层后, 本仿真采集到的"线上一帧"
//   比原来整整多了 8 个字节(7x0x55 + 0xD5), 因此:
//     - 期望长度一律 +8      : 64->72, 54->62, 50->58
//     - 所有字段偏移量一律 +8 : 例如 ARP 操作码 20->28, ICMP 类型 34->42
//   注: 上面测试点里写的偏移量仍是"帧内偏移(不含前导码)", 便于与协议文档对照;
//       代码实际比较时用 txbuf[start + 8 + 帧内偏移]。
//============================================================================
module tb_eth_top;

    reg         rxc = 0, sys_rst_n = 0;
    reg  [3:0]  rxd = 0;
    reg         rx_ctl = 0;
    wire        txc;
    wire [3:0]  txd;
    wire        tx_ctl;
    wire        led;
    wire        phy_rst_n;              // PHY 复位(本工程恒为1, 释放复位)
    // 建模 PHY 内部 RX 延迟(RGMII-ID): 把喂给 DUT 的 eth_rxc 推后2ns,
    // 让 FPGA 用0°主时钟采样时, RXD 跳变(对齐原始rxc)恰好落在数据眼中央。
    wire        rxc_dly;
    assign #2 rxc_dly = rxc;            // 模拟 PHY 内部 2ns RX 延迟
    integer     errors = 0;
    integer     j;

    // 顶层新增 rtl/phy/preamble_inserter.v 之后, 采集到的"线上一帧"前面会多出
    //  8 个字节 = 7字节前导码(0x55) + 1字节帧起始定界符(0xD5)。
    //  下面所有字段比较都用 "txbuf[start + PREAM + 帧内偏移]" 来定位,
    //  这样既保留了协议文档里的"帧内偏移"写法, 又不会与新插入的前导码错位。
    parameter   PREAM = 8;

    // SCAN_EN=0: 仿真不跑 IDELAY 扫描(tap 固定 0 直通)
    eth_top #(.SCAN_EN(0)) dut (
        .eth_rxc(rxc_dly), .eth_rxd(rxd), .eth_rx_ctl(rx_ctl),
        .sys_rst_n(sys_rst_n),
        .eth_txc(txc), .eth_txd(txd), .eth_tx_ctl(tx_ctl),
        .led(led), .phy_rst_n(phy_rst_n));

    // 行为级仿真需显式例化 glbl, 供 IDDR/ODDR 的 GSR 冻结行为解析
    // (xsim 下由 $XILINX_VIVADO 的 glbl.v 自动例化, 这里不影响)
    glbl glbl ();

    always #4 rxc = ~rxc;               // 125MHz PHY 时钟

    // 激励: 以 RGMII DDR 时序发一个字节(上升沿低4位, 下降沿高4位)
    task send_byte(input [7:0] b);
        begin
            @(posedge rxc); rxd <= b[3:0]; rx_ctl <= 1'b1;
            @(negedge rxc); rxd <= b[7:4];
        end
    endtask

    reg [7:0] arp_f [0:45];
    reg [7:0] icmp_f [0:53];
    reg [7:0] udp_f [0:49];

    task send_arp;     // ARP 请求帧(46字节)
        begin
            for (j = 0; j < 7; j = j + 1) send_byte(8'h55);   // 前导码
            send_byte(8'hD5);                                   // SFD
            for (j = 0; j < 46; j = j + 1) send_byte(arp_f[j]);
            @(posedge rxc); rxd <= 0; rx_ctl <= 0;
        end
    endtask

    task send_icmp;    // ICMP Echo 请求帧(54字节, 数据 "abcdefgh")
        begin
            for (j = 0; j < 7; j = j + 1) send_byte(8'h55);
            send_byte(8'hD5);
            for (j = 0; j < 54; j = j + 1) send_byte(icmp_f[j]);
            @(posedge rxc); rxd <= 0; rx_ctl <= 0;
        end
    endtask

    task send_udp;     // UDP 帧(50字节, 12345->5000, 数据 "PING")
        begin
            for (j = 0; j < 7; j = j + 1) send_byte(8'h55);
            send_byte(8'hD5);
            for (j = 0; j < 50; j = j + 1) send_byte(udp_f[j]);
            @(posedge rxc); rxd <= 0; rx_ctl <= 0;
        end
    endtask

    // 采集: 按 RGMII 时序重组 FPGA 发出的字节
    // 采集必须"模拟真实 PHY": 以 TXC 上升沿采到的 tx_ctl 判定该字节有效。
    // 只看下降沿的 tx_ctl 会把 tx_ctl 刚拉高的半个周期误采成一个字节,
    // 导致整体偏移。
    reg [7:0] txbuf [0:255];
    integer   txcnt = 0;
    reg [3:0] lo_nib;
    reg       ctl_at_rise = 1'b0;
    always @(posedge txc) begin
        #1;
        if (tx_ctl) begin
            lo_nib      = txd;                  // 上升沿: 低4位
            ctl_at_rise = 1'b1;
        end else
            ctl_at_rise = 1'b0;
    end
    always @(negedge txc) begin
        #1;
        if (tx_ctl && ctl_at_rise) begin
            txbuf[txcnt] = {txd, lo_nib};       // 下降沿: 高4位, 拼成字节
            txcnt = txcnt + 1;
        end
    end

    // ---- 三种测试帧 ----
    initial begin
        // ARP 请求(广播, 询问 192.168.1.123)
        arp_f[0]=8'hFF; arp_f[1]=8'hFF; arp_f[2]=8'hFF; arp_f[3]=8'hFF;
        arp_f[4]=8'hFF; arp_f[5]=8'hFF; arp_f[6]=8'h00; arp_f[7]=8'h11;
        arp_f[8]=8'h22; arp_f[9]=8'h33; arp_f[10]=8'h44; arp_f[11]=8'h66;
        arp_f[12]=8'h08; arp_f[13]=8'h06; arp_f[14]=8'h00; arp_f[15]=8'h01;
        arp_f[16]=8'h08; arp_f[17]=8'h00; arp_f[18]=8'h06; arp_f[19]=8'h04;
        arp_f[20]=8'h00; arp_f[21]=8'h01; arp_f[22]=8'h00; arp_f[23]=8'h11;
        arp_f[24]=8'h22; arp_f[25]=8'h33; arp_f[26]=8'h44; arp_f[27]=8'h66;
        arp_f[28]=8'hC0; arp_f[29]=8'hA8; arp_f[30]=8'h01; arp_f[31]=8'h64;
        arp_f[32]=8'h00; arp_f[33]=8'h00; arp_f[34]=8'h00; arp_f[35]=8'h00;
        arp_f[36]=8'h00; arp_f[37]=8'h00; arp_f[38]=8'hC0; arp_f[39]=8'hA8;
        arp_f[40]=8'h01; arp_f[41]=8'h7B; arp_f[42]=8'hE6; arp_f[43]=8'hD2;
        arp_f[44]=8'hF3; arp_f[45]=8'hEB;

        // ICMP Echo 请求(数据 "abcdefgh")
        icmp_f[0]=8'h00; icmp_f[1]=8'h11; icmp_f[2]=8'h22; icmp_f[3]=8'h33;
        icmp_f[4]=8'h44; icmp_f[5]=8'h55; icmp_f[6]=8'h00; icmp_f[7]=8'h11;
        icmp_f[8]=8'h22; icmp_f[9]=8'h33; icmp_f[10]=8'h44; icmp_f[11]=8'h66;
        icmp_f[12]=8'h08; icmp_f[13]=8'h00; icmp_f[14]=8'h45; icmp_f[15]=8'h00;
        icmp_f[16]=8'h00; icmp_f[17]=8'h24; icmp_f[18]=8'h00; icmp_f[19]=8'h00;
        icmp_f[20]=8'h40; icmp_f[21]=8'h00; icmp_f[22]=8'h40; icmp_f[23]=8'h01;
        icmp_f[24]=8'hB6; icmp_f[25]=8'hA9; icmp_f[26]=8'hC0; icmp_f[27]=8'hA8;
        icmp_f[28]=8'h01; icmp_f[29]=8'h64; icmp_f[30]=8'hC0; icmp_f[31]=8'hA8;
        icmp_f[32]=8'h01; icmp_f[33]=8'h7B; icmp_f[34]=8'h08; icmp_f[35]=8'h00;
        icmp_f[36]=8'h66; icmp_f[37]=8'h68; icmp_f[38]=8'h00; icmp_f[39]=8'h01;
        icmp_f[40]=8'h00; icmp_f[41]=8'h01; icmp_f[42]=8'h61; icmp_f[43]=8'h62;
        icmp_f[44]=8'h63; icmp_f[45]=8'h64; icmp_f[46]=8'h65; icmp_f[47]=8'h66;
        icmp_f[48]=8'h67; icmp_f[49]=8'h68; icmp_f[50]=8'h7C; icmp_f[51]=8'hFE;
        icmp_f[52]=8'h5E; icmp_f[53]=8'h1E;

        // UDP(12345 -> 5000, 数据 "PING")
        udp_f[0]=8'h00; udp_f[1]=8'h11; udp_f[2]=8'h22; udp_f[3]=8'h33;
        udp_f[4]=8'h44; udp_f[5]=8'h55; udp_f[6]=8'h00; udp_f[7]=8'h11;
        udp_f[8]=8'h22; udp_f[9]=8'h33; udp_f[10]=8'h44; udp_f[11]=8'h66;
        udp_f[12]=8'h08; udp_f[13]=8'h00; udp_f[14]=8'h45; udp_f[15]=8'h00;
        udp_f[16]=8'h00; udp_f[17]=8'h20; udp_f[18]=8'h00; udp_f[19]=8'h00;
        udp_f[20]=8'h40; udp_f[21]=8'h00; udp_f[22]=8'h40; udp_f[23]=8'h11;
        udp_f[24]=8'hB6; udp_f[25]=8'h9D; udp_f[26]=8'hC0; udp_f[27]=8'hA8;
        udp_f[28]=8'h01; udp_f[29]=8'h64; udp_f[30]=8'hC0; udp_f[31]=8'hA8;
        udp_f[32]=8'h01; udp_f[33]=8'h7B; udp_f[34]=8'h30; udp_f[35]=8'h39;
        udp_f[36]=8'h13; udp_f[37]=8'h88; udp_f[38]=8'h00; udp_f[39]=8'h0C;
        udp_f[40]=8'h99; udp_f[41]=8'h54; udp_f[42]=8'h50; udp_f[43]=8'h49;
        udp_f[44]=8'h4E; udp_f[45]=8'h47; udp_f[46]=8'hED; udp_f[47]=8'hA2;
        udp_f[48]=8'h95; udp_f[49]=8'h1A;
    end

    integer start_arp, start_icmp, start_udp;

    initial begin
        sys_rst_n = 0; #30; sys_rst_n = 1;

        // 必须等 PLL 锁定 + 复位释放之后再发帧, 否则发出的帧会被漏掉
        #400;
        if (!phy_rst_n) errors = errors + 1;    // phy_rst_n 应恒为1(释放PHY复位)

        // ---- 1) ARP ----
        start_arp = txcnt;
        send_arp;
        #2000;
        // 长度: 64字节最小帧 + 8字节前导码/SFD = 72
        if (txcnt - start_arp !== 64 + PREAM) errors = errors + 1;
        // 前导码检查: 前 7 字节必须是 0x55, 第 8 字节必须是 0xD5
        for (j = 0; j < 7; j = j + 1)
            if (txbuf[start_arp+j] !== 8'h55) errors = errors + 1;
        if (txbuf[start_arp+7] !== 8'hD5)     errors = errors + 1;
        // 以下偏移均为"帧内偏移", 需跳过前导码 -> 统一加 PREAM
        if ({txbuf[start_arp+PREAM+20],txbuf[start_arp+PREAM+21]} !== 16'h0002)
                                       errors = errors + 1;   // 操作码应为2(应答)
        if ({txbuf[start_arp+PREAM+28],txbuf[start_arp+PREAM+29],
             txbuf[start_arp+PREAM+30],txbuf[start_arp+PREAM+31]}
            !== 32'hC0A8_017B)         errors = errors + 1;   // 发送方IP应为本板IP
        for (j = 42; j < 60; j = j + 1)
            if (txbuf[start_arp+PREAM+j] !== 8'h00) errors = errors + 1; // 填充区42~59应为0

        // ---- 2) ICMP ----
        start_icmp = txcnt;
        send_icmp;
        #3000;
        // 长度: 54字节Echo应答 + 8字节前导码/SFD = 62
        if (txcnt - start_icmp !== 54 + PREAM) errors = errors + 1;
        // 前导码检查
        for (j = 0; j < 7; j = j + 1)
            if (txbuf[start_icmp+j] !== 8'h55) errors = errors + 1;
        if (txbuf[start_icmp+7] !== 8'hD5)     errors = errors + 1;
        // 以下为帧内偏移, 统一加 PREAM
        if (txbuf[start_icmp+PREAM+34] !== 8'h00) errors = errors + 1; // ICMP类型应为0(应答)
        if (txbuf[start_icmp+PREAM+42] !== 8'h61) errors = errors + 1; // 数据首字节 'a'
        if (txbuf[start_icmp+PREAM+49] !== 8'h68) errors = errors + 1; // 数据末字节 'h'(边界)

        // ---- 3) UDP ----
        start_udp = txcnt;
        send_udp;
        #3000;
        // 长度: 50字节UDP回显 + 8字节前导码/SFD = 58
        if (txcnt - start_udp !== 50 + PREAM) errors = errors + 1;
        // 前导码检查
        for (j = 0; j < 7; j = j + 1)
            if (txbuf[start_udp+j] !== 8'h55) errors = errors + 1;
        if (txbuf[start_udp+7] !== 8'hD5)     errors = errors + 1;
        // 以下为帧内偏移, 统一加 PREAM
        if ({txbuf[start_udp+PREAM+36],txbuf[start_udp+PREAM+37]} !== 16'h3039)
                                       errors = errors + 1;   // 目的端口应为12345
        if (txbuf[start_udp+PREAM+42] !== 8'h50) errors = errors + 1; // 数据首字节 'P'
        if (txbuf[start_udp+PREAM+45] !== 8'h47) errors = errors + 1; // 数据末字节 'G'(边界)

        #100;
        // 唯一打印: 最终结论
        if (errors == 0) $display("==== tb_eth_top: PASS ====");
        else             $display("==== tb_eth_top: %0d 个错误 FAIL ====", errors);
        $finish;
    end

    // 看门狗
    initial begin
        #200000;
        $display("==== tb_eth_top: 超时 FAIL ====");
        $finish;
    end

endmodule
