################################################################################
# 文件：diag_cdc.xdc
# 作用：为频率计诊断模块补充【跨时钟域路径约束】
# 位置：E:\fpga_check\final_single_buffer\优化修改版\频率计模块\diag_cdc.xdc
# 日期：2026-09-26
#
# 为什么需要这个文件：
#   diag_freq_meter 把 3 个不同时钟域的信号引进来做两个同步器：
#     · cam1_pclk  域 → clk_50m 域   (cam1_vsync、cam1_pclk 分频输出)
#     · clk_out1   域 → clk_50m 域   (hdmi_out_vsync，74.25MHz → 50MHz)
#
#   cam1_pclk 已被 `set_clock_groups -asynchronous` 单独分组（见主 xdc 第 167 行），
#   所以前两条路径本来就是 false path，不需要额外处理。
#
#   但 clk_out1(74.25MHz) 和 clk_out3(50MHz) 是【同一个 MMCM 的输出】，
#   两者在同一个 clock group 里，Vivado 会对它们之间的路径做真实的
#   setup/hold 分析 —— 这正是加频率计后 WNS 变差（-2.511ns）的嫌疑来源。
#   而这条路径只是【两级同步器】的标准 CDC，应当设伪路径。
#
# 怎么用：
#   Vivado 里 Add Sources → Add or create constraints，把本文件加进工程；
#   或把下面两条 set_false_path 粘贴到 ov5640_ddr3_hdmi_full_fixed.xdc 末尾。
#
# ⚠ 若报 "no objects matched"，说明综合后层次名不同，先查实际名字：
#     get_pins -hier -filter {NAME =~ *diag_freq_meter*/p_sync_reg[0]/D}
#   然后用查到的名字替换下面的通配写法。
################################################################################

# ---- hdmi_out_vsync (clk_out1) → diag 模块两级同步器 (clk_out3) ----
set_false_path -through [get_pins -hier -filter {NAME =~ *u_diag_freq_meter*/p_sync_reg[0]/D}]

# ---- cam1_pclk 分频输出 → diag 模块边沿检测 (clk_out3) ----
#      这条理论上已被主 xdc 的 set_clock_groups -asynchronous 覆盖，
#      这里再显式声明一次作为保险（不影响其他逻辑）。
set_false_path -through [get_pins -hier -filter {NAME =~ *u_diag_freq_meter*/div_sync_reg[0]/D}]

################################################################################
# 备选做法（不推荐，除非确认 clk_out1/clk_out3 之间没有其他真实路径）：
#   set_clock_groups -asynchronous \
#        -group [get_clocks instance_name/inst/clk_out1] \
#        -group [get_clocks instance_name/inst/clk_out3]
#   这样会把两个 MMCM 输出时钟彻底分组，但会连带切断他们之间【所有】路径，
#   如果原设计里还有别的 clk_out1↔clk_out3 真实通路，会一起被误伤。
################################################################################
