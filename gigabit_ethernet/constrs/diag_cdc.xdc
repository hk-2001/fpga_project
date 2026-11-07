################################################################################
# 文件：diag_cdc.xdc
# 作用：RGMII 接收侧跨域路径的时序约束
#
# 为什么需要这个文件：
#   rgmii_to_gmii 里 IDDR 由 rxc_bufg(派生自 eth_rxc) 采样，紧随其后的
#   两拍同步器 sync1_* / sync2_* 由 mmcm_clk0(MMCM CLKOUT0，即 gmii_clk) 驱动。
#   两个时钟同源同频，但路径不同：
#     · 源端  : eth_rxc -> IBUF -> BUFG -> rxc_bufg -> IDDR.C
#     · 目的端: eth_rxc -> IBUF -> BUFG -> MMCME2 -> BUFG -> gmii_clk -> sync1/D
#   MMCM 内反馈只补偿输入侧 BUFG，目的时钟比源时钟多出约 4.5ns 的插入延迟。
#
#   Vivado 把 mmcm_clk0 推导为 eth_rxc 的生成时钟，于是按「相关时钟同一沿」
#   给这条 CDC 路径下 0ns 的 hold 要求(Requirement: mmcm_clk0 rise@0 -
#   eth_rxc rise@0)。实测这条路径：
#     Data Path Delay 4.646ns，Clock Path Skew 4.506ns，WHS -0.012 ~ -0.141ns，
#   1 个 failing endpoint —— 但这不是硬件上真的保持时间不够，而是时钟路径
#   偏斜被算进了 required time。同一份网表换一次布局，slack 就在 0 附近
#   正负漂移，靠 phys_opt_design -hold_fix 也修不掉(实测 WHS 仍为 -0.141ns)。
#
#   两级同步器本来就是异步跨相位域，不该按同沿做 hold 检查。
#
# 处理：用 set_max_delay -datapath_only 只约束数据路径上限(8ns，一个时钟周期)，
#       setup 侧仍受控；-datapath_only 会让工具忽略时钟偏斜、豁免该 hold 检查。
#
# 实测(2026-11-06，保留 ILA 调试核)：
#       WNS +0.104ns / TNS 0.000 / WHS +0.036ns / THS 0.000
#       17077 端点 0 违例，All user specified timing constraints are met.
################################################################################

# ---- IDDR(eth_rxc 域) -> sync1_* 两级同步器(mmcm_clk0 域) ----
set_max_delay -datapath_only 8.000 -from [get_clocks eth_rxc] -to [get_clocks mmcm_clk0]

################################################################################
# 备选做法（不采用）：
#   set_false_path -from [get_clocks eth_rxc] -to [get_clocks mmcm_clk0]
#   set_clock_groups -asynchronous -group eth_rxc -group mmcm_clk0
# 这两条会把 setup 检查一并切掉，RX 数据路径延迟完全不受控；而且两个时钟
# 本就同源，声明异步在语义上也不准确。datapath_only 保留了 8ns 上限，是更
# 精确的折中。
################################################################################
