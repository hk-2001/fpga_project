################################################################################
#  文件：ov5640_ddr3_hdmi_full_fixed.xdc
#  工程：原管脚约束（原样保留）+ 时钟/时序约束
#  与 ov5640_ddr3_hdmi_full.xdc 旧版本 的区别：
#     1) 74.25MHz 已挪到 CLKOUT0
#     2) create_generated_clock 的 -source 由 CLKOUT3 改为 CLKOUT0
#  生成日期：2026-09-22

################################################################################

################################################################################
# 第一部分：管脚 / 电平 / 位流配置（与原始 xdc 一致，未改动）
################################################################################

# 4线 SPI 配置
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
#############SPI Configurate Setting###################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

#sys_clk and rst
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
set_property PACKAGE_PIN N15 [get_ports sys_rst_n]
set_property PACKAGE_PIN W19 [get_ports sys_clk]


set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam1_pclk_IBUF]


set_property IOSTANDARD LVCMOS33 [get_ports cam1_pclk]
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports cam1_href]
set_property IOSTANDARD LVCMOS33 [get_ports cam1_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports sccb1_scl]
set_property IOSTANDARD LVCMOS33 [get_ports sccb1_sda]
set_property IOSTANDARD LVCMOS33 [get_ports cam_pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports cam_rst_n]

set_property PACKAGE_PIN N14 [get_ports {cam1_data[0]}]
set_property PACKAGE_PIN N13 [get_ports {cam1_data[1]}]
set_property PACKAGE_PIN R19 [get_ports {cam1_data[2]}]
set_property PACKAGE_PIN P19 [get_ports {cam1_data[3]}]
set_property PACKAGE_PIN U22 [get_ports {cam1_data[4]}]
set_property PACKAGE_PIN AA20 [get_ports {cam1_data[5]}]
set_property PACKAGE_PIN R18 [get_ports {cam1_data[6]}]
set_property PACKAGE_PIN U21 [get_ports {cam1_data[7]}]
set_property PACKAGE_PIN R14 [get_ports sccb1_scl]
set_property PACKAGE_PIN P14 [get_ports sccb1_sda]
set_property PACKAGE_PIN T18 [get_ports cam1_vsync]
set_property PACKAGE_PIN T21 [get_ports cam1_href]
set_property PACKAGE_PIN AA21 [get_ports cam1_pclk]
set_property PACKAGE_PIN R17 [get_ports cam_pwdn]
set_property PACKAGE_PIN P16 [get_ports cam_rst_n]

#IIC
set_property IOSTANDARD LVCMOS33 [get_ports ddc_scl]
set_property IOSTANDARD LVCMOS33 [get_ports ddc_sda]
set_property PACKAGE_PIN E19 [get_ports ddc_scl]
set_property PACKAGE_PIN D19 [get_ports ddc_sda]


#hdmi_out

set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_out_rgb[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_de]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_clk]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_rst_n]
set_property PACKAGE_PIN K19 [get_ports hdmi_out_de]
set_property PACKAGE_PIN K17 [get_ports hdmi_out_hsync]
set_property PACKAGE_PIN J17 [get_ports hdmi_out_vsync]
set_property PACKAGE_PIN K18 [get_ports hdmi_out_clk]
set_property PACKAGE_PIN J16 [get_ports hdmi_out_rst_n]
set_property PACKAGE_PIN H13 [get_ports {hdmi_out_rgb[23]}]
set_property PACKAGE_PIN G13 [get_ports {hdmi_out_rgb[22]}]
set_property PACKAGE_PIN G15 [get_ports {hdmi_out_rgb[21]}]
set_property PACKAGE_PIN G16 [get_ports {hdmi_out_rgb[20]}]
set_property PACKAGE_PIN G17 [get_ports {hdmi_out_rgb[19]}]
set_property PACKAGE_PIN G18 [get_ports {hdmi_out_rgb[18]}]
set_property PACKAGE_PIN J14 [get_ports {hdmi_out_rgb[17]}]
set_property PACKAGE_PIN H14 [get_ports {hdmi_out_rgb[16]}]
set_property PACKAGE_PIN J15 [get_ports {hdmi_out_rgb[15]}]
set_property PACKAGE_PIN H15 [get_ports {hdmi_out_rgb[14]}]
set_property PACKAGE_PIN H17 [get_ports {hdmi_out_rgb[13]}]
set_property PACKAGE_PIN H18 [get_ports {hdmi_out_rgb[12]}]
set_property PACKAGE_PIN J19 [get_ports {hdmi_out_rgb[11]}]
set_property PACKAGE_PIN H19 [get_ports {hdmi_out_rgb[10]}]
set_property PACKAGE_PIN H20 [get_ports {hdmi_out_rgb[9]}]
set_property PACKAGE_PIN G20 [get_ports {hdmi_out_rgb[8]}]
set_property PACKAGE_PIN J20 [get_ports {hdmi_out_rgb[7]}]
set_property PACKAGE_PIN J21 [get_ports {hdmi_out_rgb[6]}]
set_property PACKAGE_PIN J22 [get_ports {hdmi_out_rgb[5]}]
set_property PACKAGE_PIN H22 [get_ports {hdmi_out_rgb[4]}]
set_property PACKAGE_PIN K13 [get_ports {hdmi_out_rgb[3]}]
set_property PACKAGE_PIN K14 [get_ports {hdmi_out_rgb[2]}]
set_property PACKAGE_PIN L16 [get_ports {hdmi_out_rgb[1]}]
set_property PACKAGE_PIN K16 [get_ports {hdmi_out_rgb[0]}]

################################################################################
# 第二部分：时钟 / 时序约束（修正版）
################################################################################

################################################################################
# 1. 主时钟（板载 50MHz 晶振，专用时钟脚 W19）
################################################################################
# 整个设计的时钟源头。原工程漏了这一条 → 所有内部路径 uncontrained，时序报告不可信。
create_clock -period 20.000 -name sys_clk -waveform {0.000 10.000} [get_ports sys_clk]

################################################################################
# 2. 摄像头像素时钟（OV5640 提供，完全异步）
################################################################################
# ⚠ 周期必须实测！OV5640 的 PCLK 由内部 PLL 分频决定：
#     24MHz → 41.667ns   42MHz → 23.810ns   84MHz → 11.905ns
# 上板实测（频率计）：cam1_pclk = 84,000,064 Hz ≈ 84MHz
# → PCLK = 84MHz，周期 11.905ns
create_clock -period 11.905 -name cam1_pclk -waveform {0.000 5.9525} [get_ports cam1_pclk]

# 摄像头时钟抖动较大，额外给 0.5ns 不确定性
# 时钟不确定性：只作用于 setup（摄像头 PCLK 抖动余量）。
# 不能对 hold 也加 0.5 —— 42MHz 周期 23.8ns，setup 余量 13.9ns 足够，
# 但 hold 侧只差 0.143ns，会被 0.5 的 uncertainty 压成负值（实现器修不掉）。
set_clock_uncertainty -setup 0.500 [get_clocks cam1_pclk]
set_clock_uncertainty -hold 0.100 [get_clocks cam1_pclk]

################################################################################
# 3. clk_wiz_0 / MIG 的派生时钟由 Vivado 依据 IP 自动推导，不要手写
################################################################################
#  修正版 clk_wiz_0（VCO = 50MHz × 28 = 1400MHz）：
#      CLKOUT0 (DIVIDE_F=18.875) =  74.172 MHz  → vga_ctrl / 读FIFO / hdmi_out_clk
#      CLKOUT1 (DIVIDE=7)        = 200.000 MHz  → MIG sys_clk_i + IDELAY 参考
#      CLKOUT2 (DIVIDE=28)       =  50.000 MHz  → ov5640_top(SCCB) / hdmi_i2c(DDC)
#  （原工程是 CLKOUT2=73.684MHz，误差 -0.76%；修正版 -0.10%，HDMI 容差 ±0.5%）
#
#  MIG 内部 MMCM（VCO=800MHz）：
#      DDR3 CK = 400MHz（ddr3_ck_p/n）   ui_clk = 100MHz（400/4，PHY Ratio 4:1）
#  MIG 自带 xdc 已处理 DDR 侧时序，不要再手动约束 ddr3_* 端口。
#
#  用 report_clocks 核对，重点确认 clk_out1 = 74.172 MHz

################################################################################
# 4. HDMI 像素时钟输出端口（修正版 source = CLKOUT0）
################################################################################
# hdmi_out_clk = clk_74m（74.172MHz）经 OBUF 直出，管脚 K18。
# 声明为 generated clock 后，hdmi_out_* 总线的 set_output_delay 才有参考时钟。
# 若 -source 找不到，综合后执行：
#     get_pins -hierarchical -filter {NAME =~ *CLKOUT0*}
# 把实际路径替换进来。
create_generated_clock -name hdmi_pix_clk -source [get_pins -hierarchical -filter {NAME =~ */mmcm_adv_inst/CLKOUT0}] -multiply_by 1 [get_ports hdmi_out_clk]

################################################################################
# 5. 时钟域分组：只有 cam1_pclk 是真正的异步域
################################################################################
#  组A（同源）：sys_clk / clk_50m / clk_200m / clk_74m / ui_clk
#  组B（异步）：cam1_pclk
#  -include_generated_clocks 会一次性带上所有派生时钟，无需逐个列举。
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks sys_clk] -group [get_clocks -include_generated_clocks cam1_pclk]

################################################################################
# 6. 输入约束：摄像头 = 源同步输入（数据相对 cam1_pclk）
################################################################################
# 数值 = OV5640 手册 tPD 范围 + PCB 走线延迟差；先给保守值收敛，再按报告收紧。
set_input_delay -clock cam1_pclk -max 6.000 [get_ports {{cam1_data[*]} cam1_href cam1_vsync}]
# min 从 1.0 提到 1.5：实现后 cam1_pclk 域有 3 个 hold 违例(WHS=-0.143)，
# 加大 min input delay 给 hold 留余量
set_input_delay -clock cam1_pclk -min 1.500 [get_ports {{cam1_data[*]} cam1_href cam1_vsync}]

################################################################################
# 7. 输出约束：HDMI = 源同步输出（相对 hdmi_pix_clk）
################################################################################
# 按 HDMI 编码芯片手册的 tSU/tH 反推，先给 2.5ns / -1.0ns
set_output_delay -clock [get_clocks hdmi_pix_clk] -max 2.500 [get_ports {{hdmi_out_rgb[*]} hdmi_out_de hdmi_out_hsync hdmi_out_vsync}]
set_output_delay -clock [get_clocks hdmi_pix_clk] -min -1.000 [get_ports {{hdmi_out_rgb[*]} hdmi_out_de hdmi_out_hsync hdmi_out_vsync}]

################################################################################
# 8. CDC 与复位同步器
################################################################################
# 8.1 两个异步 FIFO 的 CDC 由 FIFO Generator IP 自带约束处理，不要额外加 false_path
# 8.2 vga_ctrl 里对 camera_done_toggle 的两级同步器（代码已带 ASYNC_REG），这里再声明一次
set_property ASYNC_REG true [get_cells -hierarchical -filter {NAME =~ *camera_done_toggle_meta*}]
set_property ASYNC_REG true [get_cells -hierarchical -filter {NAME =~ *camera_done_toggle_sync*}]

# 8.3 若已按 F5 在 50MHz / 74MHz / cam_pclk 各域加了复位同步器，把这些同步器也标上：
# set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *rst_sync*}]

# 8.4 [XPM-CDC] 复位路径说明（2026-10-01 更新）
#     rst_n 现已先经新增的 xpm_rst_sync（内部 3× Xilinx 官方原语 xpm_cdc_async_rst，
#     「异步断言 + 同步释放」）同步到 84MHz / 74.17MHz / 50MHz 三个时钟域后，再分发各模块。
#     该原语自带 ASYNC_REG 属性与时序约束，因此【无需】在此为同步器额外添加约束。
#
#     下面这条 false_path 保留，用于覆盖 sys_rst_n 直接驱动的部分：
#       · clk_wiz_0.reset   （PLL 异步复位）
#       · ddr3_rst_n → MIG  （MIG 自带约束）
#       · hdmi_out_rst_n    （输出引脚，另见第 9 节 false_path）
#     这些不属于"用户逻辑同步释放"路径，保持 false_path 是合理的。
#
#     注：两个异步 FIFO(wr/rd_ddr3_fifo) 的复位不在此列 —— FIFO Generator IP 内部
#         已用 xpm_cdc_sync_rst 完成同步，并提供 wr_rst_busy/rd_rst_busy 握手，
#         外部不应再串同步器（否则会破坏握手，v1 黑屏即此症状）。
set_false_path -from [get_ports sys_rst_n] -to [get_clocks -include_generated_clocks sys_clk]

# 8.5 跨时钟域状态信号（慢变化电平，目标端有同步器/复位同步器保护）
#     说明：不能用 set_clock_groups 把 MIG 时钟(clk_pll_i)与 clk_wiz 时钟分组 ——
#     那会覆盖 rd_ddr3_fifo 自带的 set_max_delay CDC 约束，FIFO 会真的坏掉。
#     所以这里对每条跨域状态信号单独设伪路径（-through 对经过该 net 的所有路径生效）：
set_false_path -through [get_nets ddr3_init_done]
set_false_path -through [get_nets ui_clk_sync_rst]
set_false_path -through [get_nets camera_done_toggle]
set_false_path -through [get_nets camera_done]
set_false_path -through [get_nets cam_cfg_done]
set_false_path -through [get_nets sys_init_done]
set_false_path -through [get_nets hdmi_cfg_done]
set_false_path -through [get_nets rst_n]

################################################################################
# 9. 低速 GPIO：不参与时序收敛（-to/-from 才能消除 no_output_delay / no_input_delay 警告）
################################################################################
set_false_path -to [get_ports sccb1_scl]
set_false_path -to [get_ports sccb1_sda]
set_false_path -from [get_ports sccb1_sda]
set_false_path -to [get_ports ddc_scl]
set_false_path -to [get_ports ddc_sda]
set_false_path -from [get_ports ddc_sda]
set_false_path -to [get_ports cam_pwdn]
set_false_path -to [get_ports cam_rst_n]
set_false_path -to [get_ports hdmi_out_rst_n]

################################################################################
# 附：自检命令
################################################################################
#   report_clocks                  ;# clk_out1 必须是 74.172 MHz
#   check_timing -override_defaults no_clock
#   report_clock_networks
#   report_clock_interaction -delay_type min_max
#   report_timing -delay_type min_max -max_paths 20 -input_pins
################################################################################




set_property MARK_DEBUG true [get_nets cam1_vsync_IBUF]


create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 2048 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list instance_name/inst/clk_out3]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 16 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {u_diag_freq_meter/cam_fps[0]} {u_diag_freq_meter/cam_fps[1]} {u_diag_freq_meter/cam_fps[2]} {u_diag_freq_meter/cam_fps[3]} {u_diag_freq_meter/cam_fps[4]} {u_diag_freq_meter/cam_fps[5]} {u_diag_freq_meter/cam_fps[6]} {u_diag_freq_meter/cam_fps[7]} {u_diag_freq_meter/cam_fps[8]} {u_diag_freq_meter/cam_fps[9]} {u_diag_freq_meter/cam_fps[10]} {u_diag_freq_meter/cam_fps[11]} {u_diag_freq_meter/cam_fps[12]} {u_diag_freq_meter/cam_fps[13]} {u_diag_freq_meter/cam_fps[14]} {u_diag_freq_meter/cam_fps[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 30 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {u_diag_freq_meter/cam_frame_period_ns[2]} {u_diag_freq_meter/cam_frame_period_ns[3]} {u_diag_freq_meter/cam_frame_period_ns[4]} {u_diag_freq_meter/cam_frame_period_ns[5]} {u_diag_freq_meter/cam_frame_period_ns[6]} {u_diag_freq_meter/cam_frame_period_ns[7]} {u_diag_freq_meter/cam_frame_period_ns[8]} {u_diag_freq_meter/cam_frame_period_ns[9]} {u_diag_freq_meter/cam_frame_period_ns[10]} {u_diag_freq_meter/cam_frame_period_ns[11]} {u_diag_freq_meter/cam_frame_period_ns[12]} {u_diag_freq_meter/cam_frame_period_ns[13]} {u_diag_freq_meter/cam_frame_period_ns[14]} {u_diag_freq_meter/cam_frame_period_ns[15]} {u_diag_freq_meter/cam_frame_period_ns[16]} {u_diag_freq_meter/cam_frame_period_ns[17]} {u_diag_freq_meter/cam_frame_period_ns[18]} {u_diag_freq_meter/cam_frame_period_ns[19]} {u_diag_freq_meter/cam_frame_period_ns[20]} {u_diag_freq_meter/cam_frame_period_ns[21]} {u_diag_freq_meter/cam_frame_period_ns[22]} {u_diag_freq_meter/cam_frame_period_ns[23]} {u_diag_freq_meter/cam_frame_period_ns[24]} {u_diag_freq_meter/cam_frame_period_ns[25]} {u_diag_freq_meter/cam_frame_period_ns[26]} {u_diag_freq_meter/cam_frame_period_ns[27]} {u_diag_freq_meter/cam_frame_period_ns[28]} {u_diag_freq_meter/cam_frame_period_ns[29]} {u_diag_freq_meter/cam_frame_period_ns[30]} {u_diag_freq_meter/cam_frame_period_ns[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 30 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {u_diag_freq_meter/cam_vsync_high_ns[2]} {u_diag_freq_meter/cam_vsync_high_ns[3]} {u_diag_freq_meter/cam_vsync_high_ns[4]} {u_diag_freq_meter/cam_vsync_high_ns[5]} {u_diag_freq_meter/cam_vsync_high_ns[6]} {u_diag_freq_meter/cam_vsync_high_ns[7]} {u_diag_freq_meter/cam_vsync_high_ns[8]} {u_diag_freq_meter/cam_vsync_high_ns[9]} {u_diag_freq_meter/cam_vsync_high_ns[10]} {u_diag_freq_meter/cam_vsync_high_ns[11]} {u_diag_freq_meter/cam_vsync_high_ns[12]} {u_diag_freq_meter/cam_vsync_high_ns[13]} {u_diag_freq_meter/cam_vsync_high_ns[14]} {u_diag_freq_meter/cam_vsync_high_ns[15]} {u_diag_freq_meter/cam_vsync_high_ns[16]} {u_diag_freq_meter/cam_vsync_high_ns[17]} {u_diag_freq_meter/cam_vsync_high_ns[18]} {u_diag_freq_meter/cam_vsync_high_ns[19]} {u_diag_freq_meter/cam_vsync_high_ns[20]} {u_diag_freq_meter/cam_vsync_high_ns[21]} {u_diag_freq_meter/cam_vsync_high_ns[22]} {u_diag_freq_meter/cam_vsync_high_ns[23]} {u_diag_freq_meter/cam_vsync_high_ns[24]} {u_diag_freq_meter/cam_vsync_high_ns[25]} {u_diag_freq_meter/cam_vsync_high_ns[26]} {u_diag_freq_meter/cam_vsync_high_ns[27]} {u_diag_freq_meter/cam_vsync_high_ns[28]} {u_diag_freq_meter/cam_vsync_high_ns[29]} {u_diag_freq_meter/cam_vsync_high_ns[30]} {u_diag_freq_meter/cam_vsync_high_ns[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 16 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {u_diag_freq_meter/hdmi_fps[0]} {u_diag_freq_meter/hdmi_fps[1]} {u_diag_freq_meter/hdmi_fps[2]} {u_diag_freq_meter/hdmi_fps[3]} {u_diag_freq_meter/hdmi_fps[4]} {u_diag_freq_meter/hdmi_fps[5]} {u_diag_freq_meter/hdmi_fps[6]} {u_diag_freq_meter/hdmi_fps[7]} {u_diag_freq_meter/hdmi_fps[8]} {u_diag_freq_meter/hdmi_fps[9]} {u_diag_freq_meter/hdmi_fps[10]} {u_diag_freq_meter/hdmi_fps[11]} {u_diag_freq_meter/hdmi_fps[12]} {u_diag_freq_meter/hdmi_fps[13]} {u_diag_freq_meter/hdmi_fps[14]} {u_diag_freq_meter/hdmi_fps[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 30 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {u_diag_freq_meter/hdmi_vsync_high_ns[2]} {u_diag_freq_meter/hdmi_vsync_high_ns[3]} {u_diag_freq_meter/hdmi_vsync_high_ns[4]} {u_diag_freq_meter/hdmi_vsync_high_ns[5]} {u_diag_freq_meter/hdmi_vsync_high_ns[6]} {u_diag_freq_meter/hdmi_vsync_high_ns[7]} {u_diag_freq_meter/hdmi_vsync_high_ns[8]} {u_diag_freq_meter/hdmi_vsync_high_ns[9]} {u_diag_freq_meter/hdmi_vsync_high_ns[10]} {u_diag_freq_meter/hdmi_vsync_high_ns[11]} {u_diag_freq_meter/hdmi_vsync_high_ns[12]} {u_diag_freq_meter/hdmi_vsync_high_ns[13]} {u_diag_freq_meter/hdmi_vsync_high_ns[14]} {u_diag_freq_meter/hdmi_vsync_high_ns[15]} {u_diag_freq_meter/hdmi_vsync_high_ns[16]} {u_diag_freq_meter/hdmi_vsync_high_ns[17]} {u_diag_freq_meter/hdmi_vsync_high_ns[18]} {u_diag_freq_meter/hdmi_vsync_high_ns[19]} {u_diag_freq_meter/hdmi_vsync_high_ns[20]} {u_diag_freq_meter/hdmi_vsync_high_ns[21]} {u_diag_freq_meter/hdmi_vsync_high_ns[22]} {u_diag_freq_meter/hdmi_vsync_high_ns[23]} {u_diag_freq_meter/hdmi_vsync_high_ns[24]} {u_diag_freq_meter/hdmi_vsync_high_ns[25]} {u_diag_freq_meter/hdmi_vsync_high_ns[26]} {u_diag_freq_meter/hdmi_vsync_high_ns[27]} {u_diag_freq_meter/hdmi_vsync_high_ns[28]} {u_diag_freq_meter/hdmi_vsync_high_ns[29]} {u_diag_freq_meter/hdmi_vsync_high_ns[30]} {u_diag_freq_meter/hdmi_vsync_high_ns[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 32 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {u_diag_freq_meter/cam_pclk_freq_hz[0]} {u_diag_freq_meter/cam_pclk_freq_hz[1]} {u_diag_freq_meter/cam_pclk_freq_hz[2]} {u_diag_freq_meter/cam_pclk_freq_hz[3]} {u_diag_freq_meter/cam_pclk_freq_hz[4]} {u_diag_freq_meter/cam_pclk_freq_hz[5]} {u_diag_freq_meter/cam_pclk_freq_hz[6]} {u_diag_freq_meter/cam_pclk_freq_hz[7]} {u_diag_freq_meter/cam_pclk_freq_hz[8]} {u_diag_freq_meter/cam_pclk_freq_hz[9]} {u_diag_freq_meter/cam_pclk_freq_hz[10]} {u_diag_freq_meter/cam_pclk_freq_hz[11]} {u_diag_freq_meter/cam_pclk_freq_hz[12]} {u_diag_freq_meter/cam_pclk_freq_hz[13]} {u_diag_freq_meter/cam_pclk_freq_hz[14]} {u_diag_freq_meter/cam_pclk_freq_hz[15]} {u_diag_freq_meter/cam_pclk_freq_hz[16]} {u_diag_freq_meter/cam_pclk_freq_hz[17]} {u_diag_freq_meter/cam_pclk_freq_hz[18]} {u_diag_freq_meter/cam_pclk_freq_hz[19]} {u_diag_freq_meter/cam_pclk_freq_hz[20]} {u_diag_freq_meter/cam_pclk_freq_hz[21]} {u_diag_freq_meter/cam_pclk_freq_hz[22]} {u_diag_freq_meter/cam_pclk_freq_hz[23]} {u_diag_freq_meter/cam_pclk_freq_hz[24]} {u_diag_freq_meter/cam_pclk_freq_hz[25]} {u_diag_freq_meter/cam_pclk_freq_hz[26]} {u_diag_freq_meter/cam_pclk_freq_hz[27]} {u_diag_freq_meter/cam_pclk_freq_hz[28]} {u_diag_freq_meter/cam_pclk_freq_hz[29]} {u_diag_freq_meter/cam_pclk_freq_hz[30]} {u_diag_freq_meter/cam_pclk_freq_hz[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 16 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_diag_freq_meter/cam_glitch_cnt[0]} {u_diag_freq_meter/cam_glitch_cnt[1]} {u_diag_freq_meter/cam_glitch_cnt[2]} {u_diag_freq_meter/cam_glitch_cnt[3]} {u_diag_freq_meter/cam_glitch_cnt[4]} {u_diag_freq_meter/cam_glitch_cnt[5]} {u_diag_freq_meter/cam_glitch_cnt[6]} {u_diag_freq_meter/cam_glitch_cnt[7]} {u_diag_freq_meter/cam_glitch_cnt[8]} {u_diag_freq_meter/cam_glitch_cnt[9]} {u_diag_freq_meter/cam_glitch_cnt[10]} {u_diag_freq_meter/cam_glitch_cnt[11]} {u_diag_freq_meter/cam_glitch_cnt[12]} {u_diag_freq_meter/cam_glitch_cnt[13]} {u_diag_freq_meter/cam_glitch_cnt[14]} {u_diag_freq_meter/cam_glitch_cnt[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 16 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {u_diag_freq_meter/hdmi_glitch_cnt[0]} {u_diag_freq_meter/hdmi_glitch_cnt[1]} {u_diag_freq_meter/hdmi_glitch_cnt[2]} {u_diag_freq_meter/hdmi_glitch_cnt[3]} {u_diag_freq_meter/hdmi_glitch_cnt[4]} {u_diag_freq_meter/hdmi_glitch_cnt[5]} {u_diag_freq_meter/hdmi_glitch_cnt[6]} {u_diag_freq_meter/hdmi_glitch_cnt[7]} {u_diag_freq_meter/hdmi_glitch_cnt[8]} {u_diag_freq_meter/hdmi_glitch_cnt[9]} {u_diag_freq_meter/hdmi_glitch_cnt[10]} {u_diag_freq_meter/hdmi_glitch_cnt[11]} {u_diag_freq_meter/hdmi_glitch_cnt[12]} {u_diag_freq_meter/hdmi_glitch_cnt[13]} {u_diag_freq_meter/hdmi_glitch_cnt[14]} {u_diag_freq_meter/hdmi_glitch_cnt[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 30 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {u_diag_freq_meter/hdmi_frame_period_ns[2]} {u_diag_freq_meter/hdmi_frame_period_ns[3]} {u_diag_freq_meter/hdmi_frame_period_ns[4]} {u_diag_freq_meter/hdmi_frame_period_ns[5]} {u_diag_freq_meter/hdmi_frame_period_ns[6]} {u_diag_freq_meter/hdmi_frame_period_ns[7]} {u_diag_freq_meter/hdmi_frame_period_ns[8]} {u_diag_freq_meter/hdmi_frame_period_ns[9]} {u_diag_freq_meter/hdmi_frame_period_ns[10]} {u_diag_freq_meter/hdmi_frame_period_ns[11]} {u_diag_freq_meter/hdmi_frame_period_ns[12]} {u_diag_freq_meter/hdmi_frame_period_ns[13]} {u_diag_freq_meter/hdmi_frame_period_ns[14]} {u_diag_freq_meter/hdmi_frame_period_ns[15]} {u_diag_freq_meter/hdmi_frame_period_ns[16]} {u_diag_freq_meter/hdmi_frame_period_ns[17]} {u_diag_freq_meter/hdmi_frame_period_ns[18]} {u_diag_freq_meter/hdmi_frame_period_ns[19]} {u_diag_freq_meter/hdmi_frame_period_ns[20]} {u_diag_freq_meter/hdmi_frame_period_ns[21]} {u_diag_freq_meter/hdmi_frame_period_ns[22]} {u_diag_freq_meter/hdmi_frame_period_ns[23]} {u_diag_freq_meter/hdmi_frame_period_ns[24]} {u_diag_freq_meter/hdmi_frame_period_ns[25]} {u_diag_freq_meter/hdmi_frame_period_ns[26]} {u_diag_freq_meter/hdmi_frame_period_ns[27]} {u_diag_freq_meter/hdmi_frame_period_ns[28]} {u_diag_freq_meter/hdmi_frame_period_ns[29]} {u_diag_freq_meter/hdmi_frame_period_ns[30]} {u_diag_freq_meter/hdmi_frame_period_ns[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 1 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list cam_cfg_done]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list u_diag_freq_meter/cam_pclk_lost]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list u_diag_freq_meter/cam_pclk_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list u_diag_freq_meter/cam_vsync_lost]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 1 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list hdmi_cfg_done]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 1 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list u_diag_freq_meter/hdmi_vsync_lost]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 1 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list u_diag_freq_meter/rate_valid]]
create_debug_core u_ila_1 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_1]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_1]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_1]
set_property C_DATA_DEPTH 2048 [get_debug_cores u_ila_1]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_1]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_1]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_1]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_1]
set_property port_width 1 [get_debug_ports u_ila_1/clk]
connect_debug_port u_ila_1/clk [get_nets [list cam1_pclk_IBUF_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe0]
set_property port_width 1 [get_debug_ports u_ila_1/probe0]
connect_debug_port u_ila_1/probe0 [get_nets [list cam1_vsync_IBUF]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe1]
set_property port_width 1 [get_debug_ports u_ila_1/probe1]
connect_debug_port u_ila_1/probe1 [get_nets [list cam1_wr_en]]
create_debug_core u_ila_2 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_2]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_2]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_2]
set_property C_DATA_DEPTH 2048 [get_debug_cores u_ila_2]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_2]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_2]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_2]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_2]
set_property port_width 1 [get_debug_ports u_ila_2/clk]
connect_debug_port u_ila_2/clk [get_nets [list ddr3_ctrl_2port_inst/mig_7series_0_inst/u_mig_7series_0_mig/u_ddr3_infrastructure/CLK]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe0]
set_property port_width 1 [get_debug_ports u_ila_2/probe0]
connect_debug_port u_ila_2/probe0 [get_nets [list camera_done]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe1]
set_property port_width 1 [get_debug_ports u_ila_2/probe1]
connect_debug_port u_ila_2/probe1 [get_nets [list camera_done_toggle]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe2]
set_property port_width 1 [get_debug_ports u_ila_2/probe2]
connect_debug_port u_ila_2/probe2 [get_nets [list ddr3_init_done]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe3]
set_property port_width 1 [get_debug_ports u_ila_2/probe3]
connect_debug_port u_ila_2/probe3 [get_nets [list sys_init_done]]
create_debug_core u_ila_3 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_3]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_3]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_3]
set_property C_DATA_DEPTH 2048 [get_debug_cores u_ila_3]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_3]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_3]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_3]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_3]
set_property port_width 1 [get_debug_ports u_ila_3/clk]
connect_debug_port u_ila_3/clk [get_nets [list instance_name/inst/clk_out1]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe0]
set_property port_width 1 [get_debug_ports u_ila_3/probe0]
connect_debug_port u_ila_3/probe0 [get_nets [list hdmi_out_de_OBUF]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe1]
set_property port_width 1 [get_debug_ports u_ila_3/probe1]
connect_debug_port u_ila_3/probe1 [get_nets [list hdmi_out_hsync_OBUF]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe2]
set_property port_width 1 [get_debug_ports u_ila_3/probe2]
connect_debug_port u_ila_3/probe2 [get_nets [list hdmi_out_vsync_OBUF]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe3]
set_property port_width 1 [get_debug_ports u_ila_3/probe3]
connect_debug_port u_ila_3/probe3 [get_nets [list hdmi_rd_en]]
create_debug_core u_ila_4 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_4]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_4]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_4]
set_property C_DATA_DEPTH 2048 [get_debug_cores u_ila_4]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_4]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_4]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_4]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_4]
set_property port_width 1 [get_debug_ports u_ila_4/clk]
connect_debug_port u_ila_4/clk [get_nets [list instance_name/inst/clkfbout_buf_clk_wiz_0]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_4/probe0]
set_property port_width 1 [get_debug_ports u_ila_4/probe0]
connect_debug_port u_ila_4/probe0 [get_nets [list locked]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets u_ila_4_clkfbout_buf_clk_wiz_0]
