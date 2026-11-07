#============================================================================
# 文件名 : eth_top.xdc
# 作用   : 升腾Pro (XC7A200TFBG484-2L) 真实引脚约束
# 来源   : [野火]升腾_Pro开发板硬件规格书V1.0.1.pdf 以太网引脚表 + 电源树
# 说明   : 经规格书核对, 以下 IO 全部位于 3.3V Bank:
#            RGMII(RX/TX 共12脚) / ETH_MDC / ETH_MDIO / ETH_INIB / ETH_NRST
#              -> 均在 BANK 16, VCCIO = 3.3V (规格书: BANK15/16 共用一路
#                 3.3V VCCIO 电源)
#            KEY1(V17) -> BANK 14, 3.3V
#            LED1(M21)-> BANK 15, 3.3V
#          => RGMII/全部引脚统一 LVCMOS33
#          ETH_MDIO/ETH_MDC/ETH_INIB 当前设计未使用, 未约束;
#          ETH_NRST(PHY复位,E21) 由 phy_rst_n 输出拉高(释放PHY复位)使用。
#============================================================================

#----------------------------------------------------------------------------
# 0) 配置 Bank 电压属性 (消除 DRC CFGBVS-1 警告)
#    Bank0(配置Bank)的 VCCO = 3.3V, 故 CFGBVS 接 VCCO, CONFIG_VOLTAGE = 3.3
#----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

#----------------------------------------------------------------------------
# 1) RGMII 接收方向 (PHY -> FPGA)
#----------------------------------------------------------------------------
set_property PACKAGE_PIN C18 [get_ports eth_rxc]
set_property PACKAGE_PIN D20 [get_ports {eth_rxd[0]}]
set_property PACKAGE_PIN C20 [get_ports {eth_rxd[1]}]
set_property PACKAGE_PIN A18 [get_ports {eth_rxd[2]}]
set_property PACKAGE_PIN A19 [get_ports {eth_rxd[3]}]
set_property PACKAGE_PIN C22 [get_ports eth_rx_ctl]

#----------------------------------------------------------------------------
# 2) RGMII 发送方向 (FPGA -> PHY)
#----------------------------------------------------------------------------
set_property PACKAGE_PIN C19 [get_ports eth_txc]
set_property PACKAGE_PIN B20 [get_ports {eth_txd[0]}]
set_property PACKAGE_PIN A20 [get_ports {eth_txd[1]}]
set_property PACKAGE_PIN B21 [get_ports {eth_txd[2]}]
set_property PACKAGE_PIN A21 [get_ports {eth_txd[3]}]
set_property PACKAGE_PIN B22 [get_ports eth_tx_ctl]

#----------------------------------------------------------------------------
# 3) 复位 / 心跳灯 / PHY 复位
#----------------------------------------------------------------------------
set_property PACKAGE_PIN V17 [get_ports sys_rst_n]
set_property PACKAGE_PIN M21 [get_ports led]
set_property PACKAGE_PIN E21 [get_ports phy_rst_n]

#----------------------------------------------------------------------------
# 4) IO 电平标准  --  全部 3.3V (LVCMOS33)
#    RGMII / NRST 在 BANK 16 (3.3V)
#    KEY1 在 BANK 14 (3.3V); LED 在 BANK 15 (3.3V)
#----------------------------------------------------------------------------
set_property IOSTANDARD LVCMOS33 [get_ports eth_rxc]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rxd[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rxd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rxd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rxd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports eth_rx_ctl]
set_property IOSTANDARD LVCMOS33 [get_ports eth_txc]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_txd[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_txd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_txd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_txd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports eth_tx_ctl]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports led]
set_property IOSTANDARD LVCMOS33 [get_ports phy_rst_n]

#----------------------------------------------------------------------------
# 5) 时钟约束
#    eth_rxc = PHY 送来的 125MHz 接收时钟, 周期 8ns
#    (升腾Pro 的 C18 落在 BANK16 普通 IO 而非 CC 脚, clk_gen.v 已用 BUFG 接入 MMCM)
#----------------------------------------------------------------------------
create_clock -period 8.000 -name eth_rxc -waveform {0.000 4.000} [get_ports eth_rxc]

# TX 转发时钟: eth_txc 由 gmii_to_rgmii 内 ODDR 从 mmcm_clk0(clk125) 产生,
# 用生成时钟描述它, 输出延迟必须相对该转发时钟(而非原始输入时钟)分析,
# 否则会因 MMCM 插入延迟差异造成约 12ns 的时序分析偏差。
create_generated_clock -name eth_txc -source [get_pins u_tx_conv/u_oddr_clk/C] -divide_by 1 [get_ports eth_txc]

#----------------------------------------------------------------------------
# 6) 输入/输出延迟 (板内走线很短, 用宽松值即可)
#    RX: PHY 用 eth_rxc 边沿对齐发送数据, FPGA 内部用 rxc_bufg 采样并经 IDELAYE2 调相
#    TX: 相对转发时钟 eth_txc 约束(源同步)
#----------------------------------------------------------------------------
# RX input delay (相对 PHY 送来的 eth_rxc); XDC 不支持循环, 且 -min 的负号会
# 被解析器误判, 故逐位用 -max 单独约束。
set_input_delay -clock eth_rxc -max 2.000 [get_ports {eth_rxd[0]}]
set_input_delay -clock eth_rxc -max 2.000 [get_ports {eth_rxd[1]}]
set_input_delay -clock eth_rxc -max 2.000 [get_ports {eth_rxd[2]}]
set_input_delay -clock eth_rxc -max 2.000 [get_ports {eth_rxd[3]}]
set_input_delay -clock eth_rxc -max 2.000 [get_ports eth_rx_ctl]
# TX output delay (相对 FPGA 转发的 eth_txc)
set_output_delay -clock eth_txc -max 2.000 [get_ports {eth_txd[0]}]
set_output_delay -clock eth_txc -max 2.000 [get_ports {eth_txd[1]}]
set_output_delay -clock eth_txc -max 2.000 [get_ports {eth_txd[2]}]
set_output_delay -clock eth_txc -max 2.000 [get_ports {eth_txd[3]}]
set_output_delay -clock eth_txc -max 2.000 [get_ports eth_tx_ctl]



create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list u_pll/gmii_clk]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 8 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {arb_tx_data[0]} {arb_tx_data[1]} {arb_tx_data[2]} {arb_tx_data[3]} {arb_tx_data[4]} {arb_tx_data[5]} {arb_tx_data[6]} {arb_tx_data[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 16 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {eth_type[0]} {eth_type[1]} {eth_type[2]} {eth_type[3]} {eth_type[4]} {eth_type[5]} {eth_type[6]} {eth_type[7]} {eth_type[8]} {eth_type[9]} {eth_type[10]} {eth_type[11]} {eth_type[12]} {eth_type[13]} {eth_type[14]} {eth_type[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 48 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {mac_dmac[0]} {mac_dmac[1]} {mac_dmac[2]} {mac_dmac[3]} {mac_dmac[4]} {mac_dmac[5]} {mac_dmac[6]} {mac_dmac[7]} {mac_dmac[8]} {mac_dmac[9]} {mac_dmac[10]} {mac_dmac[11]} {mac_dmac[12]} {mac_dmac[13]} {mac_dmac[14]} {mac_dmac[15]} {mac_dmac[16]} {mac_dmac[17]} {mac_dmac[18]} {mac_dmac[19]} {mac_dmac[20]} {mac_dmac[21]} {mac_dmac[22]} {mac_dmac[23]} {mac_dmac[24]} {mac_dmac[25]} {mac_dmac[26]} {mac_dmac[27]} {mac_dmac[28]} {mac_dmac[29]} {mac_dmac[30]} {mac_dmac[31]} {mac_dmac[32]} {mac_dmac[33]} {mac_dmac[34]} {mac_dmac[35]} {mac_dmac[36]} {mac_dmac[37]} {mac_dmac[38]} {mac_dmac[39]} {mac_dmac[40]} {mac_dmac[41]} {mac_dmac[42]} {mac_dmac[43]} {mac_dmac[44]} {mac_dmac[45]} {mac_dmac[46]} {mac_dmac[47]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 21 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {dbg_rx[0]} {dbg_rx[1]} {dbg_rx[2]} {dbg_rx[3]} {dbg_rx[4]} {dbg_rx[5]} {dbg_rx[6]} {dbg_rx[7]} {dbg_rx[8]} {dbg_rx[9]} {dbg_rx[10]} {dbg_rx[11]} {dbg_rx[12]} {dbg_rx[13]} {dbg_rx[14]} {dbg_rx[15]} {dbg_rx[16]} {dbg_rx[17]} {dbg_rx[18]} {dbg_rx[19]} {dbg_rx[20]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 8 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {gmii_rxd[0]} {gmii_rxd[1]} {gmii_rxd[2]} {gmii_rxd[3]} {gmii_rxd[4]} {gmii_rxd[5]} {gmii_rxd[6]} {gmii_rxd[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 8 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {mac_data[0]} {mac_data[1]} {mac_data[2]} {mac_data[3]} {mac_data[4]} {mac_data[5]} {mac_data[6]} {mac_data[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 48 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {mac_smac[0]} {mac_smac[1]} {mac_smac[2]} {mac_smac[3]} {mac_smac[4]} {mac_smac[5]} {mac_smac[6]} {mac_smac[7]} {mac_smac[8]} {mac_smac[9]} {mac_smac[10]} {mac_smac[11]} {mac_smac[12]} {mac_smac[13]} {mac_smac[14]} {mac_smac[15]} {mac_smac[16]} {mac_smac[17]} {mac_smac[18]} {mac_smac[19]} {mac_smac[20]} {mac_smac[21]} {mac_smac[22]} {mac_smac[23]} {mac_smac[24]} {mac_smac[25]} {mac_smac[26]} {mac_smac[27]} {mac_smac[28]} {mac_smac[29]} {mac_smac[30]} {mac_smac[31]} {mac_smac[32]} {mac_smac[33]} {mac_smac[34]} {mac_smac[35]} {mac_smac[36]} {mac_smac[37]} {mac_smac[38]} {mac_smac[39]} {mac_smac[40]} {mac_smac[41]} {mac_smac[42]} {mac_smac[43]} {mac_smac[44]} {mac_smac[45]} {mac_smac[46]} {mac_smac[47]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 32 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {dbg_prot[0]} {dbg_prot[1]} {dbg_prot[2]} {dbg_prot[3]} {dbg_prot[4]} {dbg_prot[5]} {dbg_prot[6]} {dbg_prot[7]} {dbg_prot[8]} {dbg_prot[9]} {dbg_prot[10]} {dbg_prot[11]} {dbg_prot[12]} {dbg_prot[13]} {dbg_prot[14]} {dbg_prot[15]} {dbg_prot[16]} {dbg_prot[17]} {dbg_prot[18]} {dbg_prot[19]} {dbg_prot[20]} {dbg_prot[21]} {dbg_prot[22]} {dbg_prot[23]} {dbg_prot[24]} {dbg_prot[25]} {dbg_prot[26]} {dbg_prot[27]} {dbg_prot[28]} {dbg_prot[29]} {dbg_prot[30]} {dbg_prot[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 1 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list arb_tx_en]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 1 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list arp_gnt]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list arp_reply_en]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list gmii_rx_dv]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list gmii_rx_er]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 1 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list icmp_gnt]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 1 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list icmp_reply_en]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 1 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list ip_ok]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe16]
set_property port_width 1 [get_debug_ports u_ila_0/probe16]
connect_debug_port u_ila_0/probe16 [get_nets [list mac_crc_ok]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe17]
set_property port_width 1 [get_debug_ports u_ila_0/probe17]
connect_debug_port u_ila_0/probe17 [get_nets [list mac_en]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe18]
set_property port_width 1 [get_debug_ports u_ila_0/probe18]
connect_debug_port u_ila_0/probe18 [get_nets [list mac_eof]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe19]
set_property port_width 1 [get_debug_ports u_ila_0/probe19]
connect_debug_port u_ila_0/probe19 [get_nets [list mac_sof]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe20]
set_property port_width 1 [get_debug_ports u_ila_0/probe20]
connect_debug_port u_ila_0/probe20 [get_nets [list rst]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe21]
set_property port_width 1 [get_debug_ports u_ila_0/probe21]
connect_debug_port u_ila_0/probe21 [get_nets [list udp_gnt]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe22]
set_property port_width 1 [get_debug_ports u_ila_0/probe22]
connect_debug_port u_ila_0/probe22 [get_nets [list udp_pkt_en]]
create_debug_core u_ila_1 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_1]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_1]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_1]
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_1]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_1]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_1]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_1]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_1]
set_property port_width 1 [get_debug_ports u_ila_1/clk]
connect_debug_port u_ila_1/clk [get_nets [list u_pll/eth_rxc_bufg]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe0]
set_property port_width 1 [get_debug_ports u_ila_1/probe0]
connect_debug_port u_ila_1/probe0 [get_nets [list pll_locked]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets u_ila_1_eth_rxc_bufg]
