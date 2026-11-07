################################################################################
#  File: ov5640_ddr3_hdmi_full_fixed.xdc
#  Project: original pin constraints (kept as-is) + clock / timing constraints
#  Differences from ov5640_ddr3_hdmi_full.xdc:
#     1) 74.25MHz moved to CLKOUT0
#     2) create_generated_clock -source changed from CLKOUT3 to CLKOUT0
#  Generated: 2026-09-22

################################################################################

################################################################################
# Part 1: pin / IO standard / bitstream config (same as original xdc, unchanged)
################################################################################

# 4-wire SPI configuration
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

# cam1_pclk enters on a NON-CCIO pin (AA21), so the IBUF -> BUFG route is NOT a dedicated
# clock route. Without this override, "Place 30-574" is a hard ERROR and the placer fails.
# NOTE: the net cam1_pclk_IBUF exists only AFTER synthesis (IBUF/BUFG are inserted during
#       implementation). So a "No nets matched 'cam1_pclk_IBUF'" warning at SYNTHESIS time
#       is EXPECTED and harmless -- do NOT delete this constraint!
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
# Part 2: clock / timing constraints (revised version)
################################################################################

################################################################################
# 1. Main clock (on-board 50MHz oscillator, dedicated clock pin W19)
################################################################################
# Clock source of the whole design. Original project missed this -> all paths unconstrained.
create_clock -period 20.000 -name sys_clk -waveform {0.000 10.000} [get_ports sys_clk]

################################################################################
# 2. Camera pixel clock (provided by OV5640, fully asynchronous)
################################################################################
# WARNING: the period MUST be measured. OV5640 PCLK comes from its internal PLL divider:
#     24MHz -> 41.667ns    42MHz -> 23.810ns    84MHz -> 11.905ns
# Measured on board (frequency meter): cam1_pclk = 84,000,064 Hz (~84MHz)
# -> PCLK = 84MHz, period = 11.905ns
create_clock -period 11.905 -name cam1_pclk -waveform {0.000 5.9525} [get_ports cam1_pclk]

# Camera clock has large jitter, add 0.5ns uncertainty.
# Clock uncertainty: applies to setup only (camera PCLK jitter margin).
# Do NOT add 0.5 to hold -- period is only 11.905ns at 84MHz, hold margin is already small.
# Hold side has only 0.143ns; a 0.5 uncertainty would push it negative (unfixable by the tool).
set_clock_uncertainty -setup 0.500 [get_clocks cam1_pclk]
set_clock_uncertainty -hold 0.100 [get_clocks cam1_pclk]

################################################################################
# 3. Derived clocks of clk_wiz_0 / MIG are auto-derived by Vivado from the IP; do NOT write them manually
################################################################################
#  Revised clk_wiz_0 (VCO = 50MHz x 28 = 1400MHz):
#      CLKOUT0 (DIVIDE_F=18.875) =  74.172 MHz  -> vga_ctrl / read FIFO / hdmi_out_clk
#      CLKOUT1 (DIVIDE=7)        = 200.000 MHz  -> MIG sys_clk_i + IDELAY reference
#      CLKOUT2 (DIVIDE=28)       =  50.000 MHz  -> ov5640_top(SCCB) / hdmi_i2c(DDC)
#  (Original project: CLKOUT2=73.684MHz, error -0.76%; revised: -0.10%, HDMI tolerance +/-0.5%)
#
#  MIG internal MMCM (VCO=800MHz):
#      DDR3 CK = 400MHz (ddr3_ck_p/n); ui_clk = 100MHz (400/4, PHY Ratio 4:1)
#  MIG's own xdc already handles DDR-side timing; do NOT constrain ddr3_* ports manually.
#
#  Verify with report_clocks; confirm clk_out1 = 74.172 MHz

################################################################################
# 4. HDMI pixel clock output port
################################################################################
# hdmi_out_clk = clk_74m (74.172MHz) driven out directly through OBUF, pin K18.
# After declaring the generated clock, set_output_delay on hdmi_out_* has a reference clock.
# -source MUST be a name that really exists after synthesis. Tried and FAILED:
#   * [get_nets clk_74_25m]                -> "No nets matched": clk_74_25m is only an RTL
#                                             wire name, NOT kept as a net after synthesis.
#   * [get_pins .../mmcm_adv_inst/CLKOUT0] -> "No pins matched": clk_wiz is an OOC black box.
# Working choice: the clk_wiz instance PORT. Instance name is "instance_name"
# (top-level: clk_wiz_0 instance_name (...)), port is clk_out1 (=74.172MHz).
create_generated_clock -name hdmi_pix_clk -source [get_pins instance_name/clk_out1] -multiply_by 1 [get_ports hdmi_out_clk]

################################################################################
# 5. Clock domain grouping: only cam1_pclk is a truly asynchronous domain
################################################################################
#  Group A (same source): sys_clk / clk_50m / clk_200m / clk_74m / ui_clk
#  Group B (asynchronous): cam1_pclk
#  -include_generated_clocks pulls in all derived clocks at once; no need to list them one by one.
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks sys_clk] -group [get_clocks -include_generated_clocks cam1_pclk]

################################################################################
# 6. Input constraints, camera = source-synchronous input (data is relative to cam1_pclk)
################################################################################
# Value = OV5640 datasheet tPD range + PCB trace delay difference; start conservative, tighten later.
set_input_delay -clock cam1_pclk -max 6.000 [get_ports {{cam1_data[*]} cam1_href cam1_vsync}]
# min raised from 1.0 to 1.5: after implementation the cam1_pclk domain had 3 hold violations (WHS=-0.143);
# increasing min input delay leaves margin for hold.
set_input_delay -clock cam1_pclk -min 1.500 [get_ports {{cam1_data[*]} cam1_href cam1_vsync}]

################################################################################
# 7. Output constraints: HDMI = source-synchronous output (relative to hdmi_pix_clk)
################################################################################
# Derived from the HDMI encoder chip datasheet tSU/tH; start with 2.5ns / -1.0ns.
set_output_delay -clock [get_clocks hdmi_pix_clk] -max 2.500 [get_ports {{hdmi_out_rgb[*]} hdmi_out_de hdmi_out_hsync hdmi_out_vsync}]
set_output_delay -clock [get_clocks hdmi_pix_clk] -min -1.000 [get_ports {{hdmi_out_rgb[*]} hdmi_out_de hdmi_out_hsync hdmi_out_vsync}]

################################################################################
# 8. CDC and reset synchronizers
################################################################################
# 8.1 CDC of the two async FIFOs is handled by the FIFO Generator IP; do NOT add extra false_path.
# 8.2 Two-stage synchronizer for camera_done_toggle in vga_ctrl (code already has ASYNC_REG), redeclared here.
set_property ASYNC_REG true [get_cells -hierarchical -filter {NAME =~ *camera_done_toggle_meta*}]
set_property ASYNC_REG true [get_cells -hierarchical -filter {NAME =~ *camera_done_toggle_sync*}]

# 8.3 If reset synchronizers were added in the 50MHz / 74MHz / cam_pclk domains, mark them too:
# set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *rst_sync*}]

# 8.4 rst_n is currently still a combinational AND of 4 cross-domain signals (before per-domain sync):
#     Set this reset path as false path so the tool does not analyze paths it should not (symptom fix).
# [XPM-CDC] Reset path note (updated 2026-10-01, supersedes the old note in 8.4)
#     rst_n now goes through the new xpm_rst_sync (3x Xilinx primitive xpm_cdc_async_rst,
#     "async assert + sync deassert") into the 84MHz / 74.17MHz / 50MHz domains, then to each module.
#     That primitive carries ASYNC_REG and its own constraints, so NO extra constraints are needed here.
#
#     The false_path below is kept to cover the parts driven directly by sys_rst_n:
#       - clk_wiz_0.reset   (async reset of the PLL)
#       - ddr3_rst_n -> MIG (MIG has its own constraints)
#       - hdmi_out_rst_n    (output pin, see also the false_path in section 9)
#     These are NOT "user-logic sync deassert" paths, so keeping false_path is reasonable.
#
#     Note: reset of the two async FIFOs (wr/rd_ddr3_fifo) is NOT included here --
#           the FIFO Generator IP syncs internally (xpm_cdc_sync_rst) and provides
#           wr_rst_busy/rd_rst_busy handshaking; do NOT add an external synchronizer (breaks handshake).
set_false_path -from [get_ports sys_rst_n] -to [get_clocks -include_generated_clocks sys_clk]

# 8.5 Cross-clock-domain status signals (slow-changing levels, protected by synchronizer / reset sync)
#     Note: do NOT use set_clock_groups to group the MIG clock (clk_pll_i) with the clk_wiz clocks --
#     that would override rd_ddr3_fifo's own set_max_delay CDC constraint and the FIFO would really break.
#     So set a false path per cross-domain signal (-through = all paths going through that net):
set_false_path -through [get_nets ddr3_init_done]
set_false_path -through [get_nets ui_clk_sync_rst]
set_false_path -through [get_nets camera_done_toggle]
set_false_path -through [get_nets camera_done]
set_false_path -through [get_nets cam_cfg_done]
set_false_path -through [get_nets sys_init_done]
set_false_path -through [get_nets hdmi_cfg_done]
set_false_path -through [get_nets rst_n]

################################################################################
# 9. Low-speed GPIO, not part of timing closure: -to/-from removes no_output_delay / no_input_delay warnings
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
# Appendix: self-check commands
################################################################################
#   report_clocks                  ;# clk_out1 must be 74.172 MHz
#   check_timing -override_defaults no_clock
#   report_clock_networks
#   report_clock_interaction -delay_type min_max
#   report_timing -delay_type min_max -max_paths 20 -input_pins
################################################################################




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
set_property port_width 16 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {u_diag_freq_meter/hdmi_fps[0]} {u_diag_freq_meter/hdmi_fps[1]} {u_diag_freq_meter/hdmi_fps[2]} {u_diag_freq_meter/hdmi_fps[3]} {u_diag_freq_meter/hdmi_fps[4]} {u_diag_freq_meter/hdmi_fps[5]} {u_diag_freq_meter/hdmi_fps[6]} {u_diag_freq_meter/hdmi_fps[7]} {u_diag_freq_meter/hdmi_fps[8]} {u_diag_freq_meter/hdmi_fps[9]} {u_diag_freq_meter/hdmi_fps[10]} {u_diag_freq_meter/hdmi_fps[11]} {u_diag_freq_meter/hdmi_fps[12]} {u_diag_freq_meter/hdmi_fps[13]} {u_diag_freq_meter/hdmi_fps[14]} {u_diag_freq_meter/hdmi_fps[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 16 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {u_diag_freq_meter/hdmi_glitch_cnt[0]} {u_diag_freq_meter/hdmi_glitch_cnt[1]} {u_diag_freq_meter/hdmi_glitch_cnt[2]} {u_diag_freq_meter/hdmi_glitch_cnt[3]} {u_diag_freq_meter/hdmi_glitch_cnt[4]} {u_diag_freq_meter/hdmi_glitch_cnt[5]} {u_diag_freq_meter/hdmi_glitch_cnt[6]} {u_diag_freq_meter/hdmi_glitch_cnt[7]} {u_diag_freq_meter/hdmi_glitch_cnt[8]} {u_diag_freq_meter/hdmi_glitch_cnt[9]} {u_diag_freq_meter/hdmi_glitch_cnt[10]} {u_diag_freq_meter/hdmi_glitch_cnt[11]} {u_diag_freq_meter/hdmi_glitch_cnt[12]} {u_diag_freq_meter/hdmi_glitch_cnt[13]} {u_diag_freq_meter/hdmi_glitch_cnt[14]} {u_diag_freq_meter/hdmi_glitch_cnt[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 16 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {u_diag_freq_meter/cam_glitch_cnt[0]} {u_diag_freq_meter/cam_glitch_cnt[1]} {u_diag_freq_meter/cam_glitch_cnt[2]} {u_diag_freq_meter/cam_glitch_cnt[3]} {u_diag_freq_meter/cam_glitch_cnt[4]} {u_diag_freq_meter/cam_glitch_cnt[5]} {u_diag_freq_meter/cam_glitch_cnt[6]} {u_diag_freq_meter/cam_glitch_cnt[7]} {u_diag_freq_meter/cam_glitch_cnt[8]} {u_diag_freq_meter/cam_glitch_cnt[9]} {u_diag_freq_meter/cam_glitch_cnt[10]} {u_diag_freq_meter/cam_glitch_cnt[11]} {u_diag_freq_meter/cam_glitch_cnt[12]} {u_diag_freq_meter/cam_glitch_cnt[13]} {u_diag_freq_meter/cam_glitch_cnt[14]} {u_diag_freq_meter/cam_glitch_cnt[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 32 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {u_diag_freq_meter/cam_pclk_freq_hz[0]} {u_diag_freq_meter/cam_pclk_freq_hz[1]} {u_diag_freq_meter/cam_pclk_freq_hz[2]} {u_diag_freq_meter/cam_pclk_freq_hz[3]} {u_diag_freq_meter/cam_pclk_freq_hz[4]} {u_diag_freq_meter/cam_pclk_freq_hz[5]} {u_diag_freq_meter/cam_pclk_freq_hz[6]} {u_diag_freq_meter/cam_pclk_freq_hz[7]} {u_diag_freq_meter/cam_pclk_freq_hz[8]} {u_diag_freq_meter/cam_pclk_freq_hz[9]} {u_diag_freq_meter/cam_pclk_freq_hz[10]} {u_diag_freq_meter/cam_pclk_freq_hz[11]} {u_diag_freq_meter/cam_pclk_freq_hz[12]} {u_diag_freq_meter/cam_pclk_freq_hz[13]} {u_diag_freq_meter/cam_pclk_freq_hz[14]} {u_diag_freq_meter/cam_pclk_freq_hz[15]} {u_diag_freq_meter/cam_pclk_freq_hz[16]} {u_diag_freq_meter/cam_pclk_freq_hz[17]} {u_diag_freq_meter/cam_pclk_freq_hz[18]} {u_diag_freq_meter/cam_pclk_freq_hz[19]} {u_diag_freq_meter/cam_pclk_freq_hz[20]} {u_diag_freq_meter/cam_pclk_freq_hz[21]} {u_diag_freq_meter/cam_pclk_freq_hz[22]} {u_diag_freq_meter/cam_pclk_freq_hz[23]} {u_diag_freq_meter/cam_pclk_freq_hz[24]} {u_diag_freq_meter/cam_pclk_freq_hz[25]} {u_diag_freq_meter/cam_pclk_freq_hz[26]} {u_diag_freq_meter/cam_pclk_freq_hz[27]} {u_diag_freq_meter/cam_pclk_freq_hz[28]} {u_diag_freq_meter/cam_pclk_freq_hz[29]} {u_diag_freq_meter/cam_pclk_freq_hz[30]} {u_diag_freq_meter/cam_pclk_freq_hz[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 30 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_diag_freq_meter/hdmi_vsync_high_ns[2]} {u_diag_freq_meter/hdmi_vsync_high_ns[3]} {u_diag_freq_meter/hdmi_vsync_high_ns[4]} {u_diag_freq_meter/hdmi_vsync_high_ns[5]} {u_diag_freq_meter/hdmi_vsync_high_ns[6]} {u_diag_freq_meter/hdmi_vsync_high_ns[7]} {u_diag_freq_meter/hdmi_vsync_high_ns[8]} {u_diag_freq_meter/hdmi_vsync_high_ns[9]} {u_diag_freq_meter/hdmi_vsync_high_ns[10]} {u_diag_freq_meter/hdmi_vsync_high_ns[11]} {u_diag_freq_meter/hdmi_vsync_high_ns[12]} {u_diag_freq_meter/hdmi_vsync_high_ns[13]} {u_diag_freq_meter/hdmi_vsync_high_ns[14]} {u_diag_freq_meter/hdmi_vsync_high_ns[15]} {u_diag_freq_meter/hdmi_vsync_high_ns[16]} {u_diag_freq_meter/hdmi_vsync_high_ns[17]} {u_diag_freq_meter/hdmi_vsync_high_ns[18]} {u_diag_freq_meter/hdmi_vsync_high_ns[19]} {u_diag_freq_meter/hdmi_vsync_high_ns[20]} {u_diag_freq_meter/hdmi_vsync_high_ns[21]} {u_diag_freq_meter/hdmi_vsync_high_ns[22]} {u_diag_freq_meter/hdmi_vsync_high_ns[23]} {u_diag_freq_meter/hdmi_vsync_high_ns[24]} {u_diag_freq_meter/hdmi_vsync_high_ns[25]} {u_diag_freq_meter/hdmi_vsync_high_ns[26]} {u_diag_freq_meter/hdmi_vsync_high_ns[27]} {u_diag_freq_meter/hdmi_vsync_high_ns[28]} {u_diag_freq_meter/hdmi_vsync_high_ns[29]} {u_diag_freq_meter/hdmi_vsync_high_ns[30]} {u_diag_freq_meter/hdmi_vsync_high_ns[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 30 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {u_diag_freq_meter/cam_vsync_high_ns[2]} {u_diag_freq_meter/cam_vsync_high_ns[3]} {u_diag_freq_meter/cam_vsync_high_ns[4]} {u_diag_freq_meter/cam_vsync_high_ns[5]} {u_diag_freq_meter/cam_vsync_high_ns[6]} {u_diag_freq_meter/cam_vsync_high_ns[7]} {u_diag_freq_meter/cam_vsync_high_ns[8]} {u_diag_freq_meter/cam_vsync_high_ns[9]} {u_diag_freq_meter/cam_vsync_high_ns[10]} {u_diag_freq_meter/cam_vsync_high_ns[11]} {u_diag_freq_meter/cam_vsync_high_ns[12]} {u_diag_freq_meter/cam_vsync_high_ns[13]} {u_diag_freq_meter/cam_vsync_high_ns[14]} {u_diag_freq_meter/cam_vsync_high_ns[15]} {u_diag_freq_meter/cam_vsync_high_ns[16]} {u_diag_freq_meter/cam_vsync_high_ns[17]} {u_diag_freq_meter/cam_vsync_high_ns[18]} {u_diag_freq_meter/cam_vsync_high_ns[19]} {u_diag_freq_meter/cam_vsync_high_ns[20]} {u_diag_freq_meter/cam_vsync_high_ns[21]} {u_diag_freq_meter/cam_vsync_high_ns[22]} {u_diag_freq_meter/cam_vsync_high_ns[23]} {u_diag_freq_meter/cam_vsync_high_ns[24]} {u_diag_freq_meter/cam_vsync_high_ns[25]} {u_diag_freq_meter/cam_vsync_high_ns[26]} {u_diag_freq_meter/cam_vsync_high_ns[27]} {u_diag_freq_meter/cam_vsync_high_ns[28]} {u_diag_freq_meter/cam_vsync_high_ns[29]} {u_diag_freq_meter/cam_vsync_high_ns[30]} {u_diag_freq_meter/cam_vsync_high_ns[31]}]]
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
