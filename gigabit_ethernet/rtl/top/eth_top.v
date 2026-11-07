//============================================================================
// 模块名   : eth_top  顶层
// 功能     : 完整以太网协议栈: RGMII收发转换 -> MAC -> ARP/IP ->
//            ICMP(Ping回显)/UDP(端口5000回显) -> 发送仲裁 -> RGMII发送
// 时钟方案 : MMCM(clk_gen) 以 PHY 的 RXC 为输入, 输出 0° 主时钟 gmii_clk
//            与 200MHz IDELAY 参考钟; RX 采样用引脚时钟 rxc_bufg。
//============================================================================
module eth_top #(
    parameter [47:0] BOARD_MAC      = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP       = 32'hC0A8_017B,   // 192.168.1.123
    parameter [15:0] LOCAL_UDP_PORT = 16'h1388,        // 5000
    // RX 采样相位校准:
    //   SCAN_EN=1 时循环扫描 IDELAY tap 0~31(校准模式);
    //   SCAN_EN=0(默认) 时 tap 固定为 IDELAY_TAP。
    //   本板实测命中 tap = 20(约 1.56ns)。
    parameter        SCAN_EN        = 0,
    parameter [4:0]  IDELAY_TAP     = 5'd20
)(
    input  wire        eth_rxc,      // PHY接收时钟
    input  wire [3:0]  eth_rxd,      // PHY接收数据(DDR)
    input  wire        eth_rx_ctl,   // PHY接收控制
    input  wire        sys_rst_n,    // 复位(低有效)
    output wire        eth_txc,      // 发送时钟(FPGA转发给PHY)
    output wire [3:0]  eth_txd,      // 发送数据(DDR)
    output wire        eth_tx_ctl,   // 发送控制
    output reg         led,          // 心跳灯
    output wire        phy_rst_n     // PHY(RTL8211F)复位, 低有效 -> 拉高释放
);

    //------------------------------------------------------------------
    // 1) 时钟: RXC -> 0度主时钟 (clk_gen MMCM, 无90°输出; RX采样用0°)
    //------------------------------------------------------------------
    // MARK_DEBUG 只是"保留该网络"的综合属性, 不会增加逻辑;
    // 普通版本即使带这些属性也完全不受影响, 只有在 build_ila.tcl 里
    // 创建 ILA 核时才会被真正连到调试探针上。
    wire gmii_clk;
    (* MARK_DEBUG = "true" *) wire pll_locked;      // [调试] PLL 是否锁定
    wire idelay_refclk;                             // 【BUG】200MHz IDELAYCTRL 参考

    clk_gen u_pll (
        .eth_rxc       (eth_rxc),
        .gmii_clk      (gmii_clk),       // 0度: 全部逻辑+发送时钟源
        .idelay_refclk (idelay_refclk),  // 【BUG】200MHz -> rgmii_to_gmii
        .locked        (pll_locked)
    );

    //------------------------------------------------------------------
    // 2) 复位同步器: XPM 异步复位同步释放 (替代手写4级打拍)
    //    xpm_cdc_async_rst 自动施加 ASYNC_REG 属性, 跨器件/速度等级更稳健;
    //    PLL 未锁定时仍强制保持复位(宏本身不含此逻辑, 需外加 OR)。
    //------------------------------------------------------------------
    (* MARK_DEBUG = "true" *) wire rst;          // [调试] 内部复位(高有效)
    wire rst_n_sync;                              // XPM 输出的同步复位(低有效)
    xpm_cdc_async_rst #(
        .DEST_SYNC_FF   (4),                     // 同步级数, 与原手写一致
        .INIT_SYNC_FF   (0),
        .RST_ACTIVE_HIGH(0)                      // 0=低有效, 与 sys_rst_n 一致
    ) u_rst_sync (
        .src_arst (sys_rst_n),                   // 异步复位输入(低有效)
        .dest_clk (gmii_clk),
        .dest_arst(rst_n_sync)                   // 同步后低有效复位
    );
    assign rst = ~rst_n_sync | ~pll_locked;      // 转高有效 + 叠 PLL 锁定

    // PHY(RTL8211F)复位释放: NRST 低有效, 拉高使 PHY 退出复位开始工作。
    // 板卡上电后 PHY 由自身 POR 初始化, FPGA 配置完成后保持 NRST=1 即可。
    assign phy_rst_n = 1'b1;

    //------------------------------------------------------------------
    // 3) RGMII -> GMII (接收方向)
    //------------------------------------------------------------------
    (* MARK_DEBUG = "true" *) wire [7:0] gmii_rxd;  // [调试] RGMII解出的接收字节
    (* MARK_DEBUG = "true" *) wire       gmii_rx_dv;// [调试] 接收字节有效
    (* MARK_DEBUG = "true" *) wire       gmii_rx_er;// [调试] 接收错误信号
    wire [4:0] dbg_tap;                             // 当前IDELAY tap(扫描可见)
    wire       dbg_tap_rdy;                         // IDELAYCTRL锁定

    rgmii_to_gmii #(
        .SCAN_EN    (SCAN_EN),      // 上板=1自动扫描; 仿真传0
        .IDELAY_TAP (IDELAY_TAP)    // 定稿时填扫描命中的tap
    ) u_rx_conv (
        .rxc           (eth_rxc),
        .rxd           (eth_rxd),
        .rx_ctl        (eth_rx_ctl),
        .clk125        (gmii_clk),
        .idelay_refclk (idelay_refclk), // 200MHz参考
        .rst           (rst),
        .gmii_rxd      (gmii_rxd),
        .gmii_rx_dv    (gmii_rx_dv),
        .gmii_rx_er    (gmii_rx_er),
        .dbg_tap       (dbg_tap),
        .dbg_tap_rdy   (dbg_tap_rdy)
    );

    //------------------------------------------------------------------
    // 4) MAC接收: 帧定界 + MAC头提取 + CRC校验
    //------------------------------------------------------------------
    (* MARK_DEBUG = "true" *) wire        mac_sof;     // [调试] 帧首字节脉冲
    (* MARK_DEBUG = "true" *) wire        mac_en;      // [调试] 字节有效
    (* MARK_DEBUG = "true" *) wire        mac_eof;     // [调试] 帧尾脉冲
    (* MARK_DEBUG = "true" *) wire        mac_crc_ok;  // [调试] FCS 校验通过
    (* MARK_DEBUG = "true" *) wire [7:0]  mac_data;    // [调试] MAC 层字节流
    (* MARK_DEBUG = "true" *) wire [47:0] mac_dmac;    // [调试] 收到的目的MAC
    (* MARK_DEBUG = "true" *) wire [47:0] mac_smac;    // [调试] 收到的源MAC(回显DA来源)
    (* MARK_DEBUG = "true" *) wire [15:0] eth_type;    // [调试] 以太类型 0800/0806

    mac_rx u_mac_rx (
        .clk      (gmii_clk),
        .rst      (rst),
        .gmii_d   (gmii_rxd),
        .gmii_dv  (gmii_rx_dv),
        .sof      (mac_sof),
        .data     (mac_data),
        .en       (mac_en),
        .eof      (mac_eof),
        .dst_mac  (mac_dmac),
        .src_mac  (mac_smac),
        .eth_type (eth_type),
        .gmii_rx_er(gmii_rx_er),
        .crc_ok   (mac_crc_ok)
    );

    //------------------------------------------------------------------
    // 5) 接收解析: ARP / IP
    //------------------------------------------------------------------
    wire        arp_update_en;
    (* MARK_DEBUG = "true" *) wire arp_reply_en;   // [调试] 触发 ARP 应答
    wire [31:0] arp_update_ip, arp_req_ip;
    wire [47:0] arp_update_mac, arp_req_mac;

    arp_rx #(.BOARD_IP(BOARD_IP)) u_arp_rx (
        .clk        (gmii_clk),
        .rst        (rst),
        .sof        (mac_sof),
        .en         (mac_en),
        .data       (mac_data),
        .eth_type   (eth_type),
        .crc_ok     (mac_crc_ok),
        .update_en  (arp_update_en),
        .update_ip  (arp_update_ip),
        .update_mac (arp_update_mac),
        .reply_en   (arp_reply_en),
        .req_ip     (arp_req_ip),
        .req_mac    (arp_req_mac)
    );

    wire arp_cache_hit;
    wire [47:0] arp_cache_mac;

    arp_cache u_arp_cache (
        .clk      (gmii_clk),
        .rst      (rst),
        .wr_en    (arp_update_en),
        .wr_ip    (arp_update_ip),
        .wr_mac   (arp_update_mac),
        .query_en (1'b0),            // 板卡暂不主动发起通信, 预留查询口
        .query_ip (32'd0),
        .hit      (arp_cache_hit),
        .mac_out  (arp_cache_mac)
    );

    wire        ip_p_sof, ip_p_en, ip_p_eof;
    (* MARK_DEBUG = "true" *) wire ip_ok;          // [调试] IP包校验全通过
    wire [7:0]  ip_p_data;
    wire [15:0] ip_payload_len;
    wire [7:0]  ip_protocol;
    wire [31:0] ip_src;

    ip_rx #(.BOARD_IP(BOARD_IP)) u_ip_rx (
        .clk         (gmii_clk),
        .rst         (rst),
        .sof         (mac_sof),
        .en          (mac_en),
        .data        (mac_data),
        .eth_type    (eth_type),
        .crc_ok      (mac_crc_ok),
        .p_sof       (ip_p_sof),
        .p_data      (ip_p_data),
        .p_en        (ip_p_en),
        .p_eof       (ip_p_eof),
        .payload_len (ip_payload_len),
        .protocol    (ip_protocol),
        .src_ip      (ip_src),
        .ip_ok       (ip_ok)
    );

    //------------------------------------------------------------------
    // 6) ICMP收发: Ping回显
    //------------------------------------------------------------------
    // 三个仲裁授权信号在 ICMP/UDP 段之前声明
    //   必须在首次使用之前声明, 否则 iverilog 报错 "declared after use"。
    (* MARK_DEBUG = "true" *) wire arp_gnt;        // [调试] 总线授给 ARP
    (* MARK_DEBUG = "true" *) wire icmp_gnt;       // [调试] 总线授给 ICMP
    (* MARK_DEBUG = "true" *) wire udp_gnt;        // [调试] 总线授给 UDP

    (* MARK_DEBUG = "true" *) wire icmp_reply_en;  // [调试] 触发 Ping 应答
    wire        icmp_fifo_empty, icmp_fifo_rd;
    wire [15:0] icmp_id, icmp_seq, icmp_cksum, icmp_dlen;
    wire [7:0]  icmp_fifo_dout;
    wire        icmp_tx_req, icmp_tx_done, icmp_tx_en;
    wire [7:0]  icmp_tx_data;

    icmp_rx u_icmp_rx (
        .clk        (gmii_clk),
        .rst        (rst),
        // p_sof / p_eof / ip_ok 需按协议门控: 否则非 ICMP 的 IP 包会
        // 清空 icmp_rx 中尚未发出的回显 FIFO。ip_protocol 在帧偏移 23
        // 锁存, 早于 p_sof(偏移 34) 与 ip_ok。
        .p_sof      (ip_p_sof && (ip_protocol == 8'd1)),
        .p_en       (ip_p_en  && (ip_protocol == 8'd1)),  // 只看ICMP报文
        .p_eof      (ip_p_eof && (ip_protocol == 8'd1)),
        .p_data     (ip_p_data),
        .payload_len(ip_payload_len),
        .ip_ok      (ip_ok   && (ip_protocol == 8'd1)),
        .reply_en   (icmp_reply_en),
        .id         (icmp_id),
        .seq        (icmp_seq),
        .icmp_cksum (icmp_cksum),
        .data_len   (icmp_dlen),
        .fifo_rd    (icmp_fifo_rd),
        .fifo_dout  (icmp_fifo_dout),
        .fifo_empty (icmp_fifo_empty)
    );

    icmp_tx #(
        .BOARD_MAC (BOARD_MAC),
        .BOARD_IP  (BOARD_IP)
    ) u_icmp_tx (
        .clk        (gmii_clk),
        .rst        (rst),
        .reply_en   (icmp_reply_en),
        .id         (icmp_id),
        .seq        (icmp_seq),
        .icmp_cksum (icmp_cksum),
        .data_len   (icmp_dlen),
        .dst_mac    (mac_smac),
        .dst_ip     (ip_src),
        .req        (icmp_tx_req),
        .grant      (icmp_gnt),
        .done       (icmp_tx_done),
        .tx_en      (icmp_tx_en),
        .tx_data    (icmp_tx_data),
        .fifo_rd    (icmp_fifo_rd),
        .fifo_dout  (icmp_fifo_dout),
        .fifo_empty (icmp_fifo_empty)
    );

    //------------------------------------------------------------------
    // 7) UDP收发: 端口5000回显
    //------------------------------------------------------------------
    (* MARK_DEBUG = "true" *) wire udp_pkt_en;     // [调试] 触发 UDP 回显
    wire        udp_fifo_empty;
    wire [15:0] udp_sport, udp_ulen;
    wire [31:0] udp_rip;
    wire [47:0] udp_rmac;
    wire [7:0]  udp_fifo_dout;
    wire        udp_fifo_rd;
    wire        udp_tx_req, udp_tx_done, udp_tx_en;
    wire [7:0]  udp_tx_data;

    udp_rx #(
        .BOARD_IP       (BOARD_IP),
        .LOCAL_UDP_PORT (LOCAL_UDP_PORT)
    ) u_udp_rx (
        .clk        (gmii_clk),
        .rst        (rst),
        // 同 ICMP 侧: p_sof / p_eof / ip_ok 一并按协议(17)门控, 否则任何非 UDP
        // 的 IP 包(如 ping)都会清空 udp_rx 的回显 FIFO。
        .p_sof      (ip_p_sof && (ip_protocol == 8'd17)),
        .p_en       (ip_p_en  && (ip_protocol == 8'd17)), // 只看UDP报文
        .p_eof      (ip_p_eof && (ip_protocol == 8'd17)),
        .p_data     (ip_p_data),
        .payload_len(ip_payload_len),
        .src_ip     (ip_src),
        .src_mac    (mac_smac),
        .ip_ok      (ip_ok   && (ip_protocol == 8'd17)),
        .pkt_en     (udp_pkt_en),
        .sport      (udp_sport),
        .udp_len    (udp_ulen),
        .rip        (udp_rip),
        .rmac       (udp_rmac),
        .fifo_rd    (udp_fifo_rd),
        .fifo_dout  (udp_fifo_dout),
        .fifo_empty (udp_fifo_empty)
    );

    udp_tx #(
        .BOARD_MAC      (BOARD_MAC),
        .BOARD_IP       (BOARD_IP),
        .LOCAL_UDP_PORT (LOCAL_UDP_PORT)
    ) u_udp_tx (
        .clk        (gmii_clk),
        .rst        (rst),
        .send_en    (udp_pkt_en),
        .sport      (udp_sport),
        .udp_len    (udp_ulen),
        .dst_ip     (udp_rip),
        .dst_mac    (udp_rmac),
        .req        (udp_tx_req),
        .grant      (udp_gnt),
        .done       (udp_tx_done),
        .tx_en      (udp_tx_en),
        .tx_data    (udp_tx_data),
        .fifo_rd    (udp_fifo_rd),
        .fifo_dout  (udp_fifo_dout),
        .fifo_empty (udp_fifo_empty)
    );

    //------------------------------------------------------------------
    // 8) ARP发送 + 发送仲裁
    //------------------------------------------------------------------
    wire        arp_tx_req, arp_tx_done, arp_tx_en;
    wire [7:0]  arp_tx_data;
    // 注: arp_gnt / icmp_gnt / udp_gnt 已在第6节之前声明(见上方注释)

    arp_tx #(
        .BOARD_MAC (BOARD_MAC),
        .BOARD_IP  (BOARD_IP)
    ) u_arp_tx (
        .clk      (gmii_clk),
        .rst      (rst),
        .reply_en (arp_reply_en),
        .req_ip   (arp_req_ip),
        .req_mac  (arp_req_mac),
        .req      (arp_tx_req),
        .grant    (arp_gnt),
        .done     (arp_tx_done),
        .tx_en    (arp_tx_en),
        .tx_data  (arp_tx_data)
    );

    (* MARK_DEBUG = "true" *) wire [7:0] arb_tx_data; // [调试] 仲裁后发出的字节
    (* MARK_DEBUG = "true" *) wire       arb_tx_en;   // [调试] 发送有效(帧在发)

    tx_arbiter u_arbiter (
        .clk       (gmii_clk),
        .rst       (rst),
        .arp_req   (arp_tx_req),   .arp_done (arp_tx_done),
        .arp_data  (arp_tx_data),  .arp_en   (arp_tx_en),
        .icmp_req  (icmp_tx_req),  .icmp_done(icmp_tx_done),
        .icmp_data (icmp_tx_data), .icmp_en  (icmp_tx_en),
        .udp_req   (udp_tx_req),   .udp_done (udp_tx_done),
        .udp_data  (udp_tx_data),  .udp_en   (udp_tx_en),
        .arp_gnt   (arp_gnt),
        .icmp_gnt  (icmp_gnt),
        .udp_gnt   (udp_gnt),
        .tx_data   (arb_tx_data),
        .tx_en     (arb_tx_en)
    );

    //------------------------------------------------------------------
    // 8.5) 前导码/SFD 插入层 (以太网帧格式封装)
    //      仲裁器出来的 arb_tx_data/arb_tx_en 是"纯 MAC 帧", 从目的MAC开始,
    //      不含前导码。这里统一补齐 7字节0x55 + 1字节0xD5 再交给 PHY。
    //      放在顶层的理由与实现细节见 rtl/phy/preamble_inserter.v 文件头注释。
    //
    //      仲裁器输出为不含前导码的纯 MAC 帧, 此处补 7 字节 0x55 与
    //      1 字节 0xD5 后交给 PHY(RTL8211F 不自行产生前导码)。
    //      FCS 已在三个 TX 模块内计算并拼在帧尾, 前导码在 CRC 之后
    //      追加, 不计入校验范围(符合 802.3)。
    //------------------------------------------------------------------
    wire [7:0] phy_tx_data;     // 已带前导码+SFD 的字节流
    wire       phy_tx_en;       // 已带前导码+SFD 的发送有效

    preamble_inserter u_preamble (
        .clk    (gmii_clk),
        .rst    (rst),
        .s_data (arb_tx_data),   // 插入前: 帧从目的MAC开始
        .s_en   (arb_tx_en),
        .m_data (phy_tx_data),   // 插入后: 帧前多了 8 字节 preamble+0xD5
        .m_en   (phy_tx_en)
    );

    //------------------------------------------------------------------
    // 9) GMII -> RGMII (发送方向)
    //------------------------------------------------------------------
    gmii_to_rgmii u_tx_conv (
        .clk125    (gmii_clk),
        .rst       (rst),
        .gmii_txd  (phy_tx_data),     // 原为 arb_tx_data -> 改为带前导码的数据
        .gmii_tx_en(phy_tx_en),       // 原为 arb_tx_en   -> 改为带前导码的使能
        .txd       (eth_txd),
        .tx_ctl    (eth_tx_ctl),
        .txc       (eth_txc)
    );

    //------------------------------------------------------------------
    // 10) 调试总线(仅供 ILA 使用)
    //     把关键信号打包成 3 条总线, ILA 直接把这 3 条当作 3 个探针,
    //     位序固定, 不依赖综合后的网络名(比逐个抓信号可靠得多)。
    //     MARK_DEBUG 只是"保留网络"的属性, 不增加任何逻辑,
    //     普通版本(不建 ILA)完全不受影响。
    //------------------------------------------------------------------
    // dbg_rx 宽度 21 位: mac_crc_ok / mac_eof / mac_en / mac_sof /
    // gmii_rx_dv 各 1 位, mac_data / gmii_rxd 各 8 位。
    (* MARK_DEBUG = "true" *) wire [20:0] dbg_rx;    // 接收字节流与帧定界
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_prot;  // 协议触发 + 发送字节
    (* MARK_DEBUG = "true" *) wire [33:0] dbg_stat;  // 状态 + 源MAC低32位

    assign dbg_rx   = {mac_crc_ok, mac_eof, mac_en, mac_sof,
                       mac_data, gmii_rx_dv, gmii_rxd};
    // dbg_prot 低 16 位默认为 eth_type; SCAN_EN=1 时切换为当前 IDELAY tap。
    generate
        if (SCAN_EN) begin : G_DBG_SCAN
            assign dbg_prot = {udp_gnt, icmp_gnt, arp_gnt, arb_tx_data, arb_tx_en,
                               ip_ok, udp_pkt_en, icmp_reply_en, arp_reply_en,
                               dbg_tap_rdy, 10'h000, dbg_tap};
        end else begin : G_DBG_NORM
            assign dbg_prot = {udp_gnt, icmp_gnt, arp_gnt, arb_tx_data, arb_tx_en,
                               ip_ok, udp_pkt_en, icmp_reply_en, arp_reply_en, eth_type};
        end
    endgenerate
    assign dbg_stat = {mac_smac[31:0], rst, pll_locked};

    //------------------------------------------------------------------
    // 11) 心跳灯
    //------------------------------------------------------------------
    // led_cnt 由复位清零, 保证每次复位后心跳周期一致。
    reg [23:0] led_cnt;
    always @(posedge gmii_clk) begin
        if (rst) begin
            led_cnt <= 24'd0;
            led     <= 1'b0;
        end else begin
            led_cnt <= led_cnt + 1'b1;
            if (led_cnt == 24'hFF_FFFF)   // 计满翻转, 约0.13s@125MHz
                led <= ~led;
        end
    end

endmodule
