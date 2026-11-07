#==============================================================================
# create_project.tcl —— 一键重建 Vivado 工程
#
# 为什么不直接上传 .xpr？
#   .xpr 里写死了生成它的机器上的绝对路径，换台电脑打不开。
#   因此仓库只保留源代码 + IP 配置（.xci/.prj），用本脚本重建工程。
#
# 用法（Vivado 2018.3）：
#   方式一：Vivado Tcl Console
#     cd E:/your/path/OV5640_DDR3_HDMI_DOUBLE_BUFFER
#     source create_project.tcl
#   方式二：命令行
#     vivado -mode batch -source create_project.tcl
#
# 器件：xc7a200tfbg484-2（Artix-7 200T）
# 顶层：ov5640_ddr_hdmi
#
# 注意：
#   rtl/camera 与 rtl/hdmi 下各有一份 top_iic_copy.v / iic_shift_bit_copy.v，
#   两者模块同名，本脚本【只添加 camera 下的一份】，否则会重复定义报错。
#==============================================================================

set proj_name "ov5640_ddr_hdmi"
set root_dir  [file normalize [file dirname [info script]]]
set part      "xc7a200tfbg484-2"

puts "=================================================="
puts " 工程名 : $proj_name"
puts " 根目录 : $root_dir"
puts " 器件   : $part"
puts "=================================================="

#------------------------------------------------------------------------------
# 1) 创建工程
#------------------------------------------------------------------------------
create_project -force $proj_name "$root_dir/build/$proj_name" -part $part
set proj [current_project]
set_property target_language  Verilog        $proj
set_property source_mgmt_mode All            $proj
set_property default_lib      xil_defaultlib $proj

#------------------------------------------------------------------------------
# 2) RTL 源文件
#------------------------------------------------------------------------------
set rtl_files [list \
    "$root_dir/rtl/top/ov5640_ddr_hdmi.v"       \
    "$root_dir/rtl/camera/ov5640_top.v"         \
    "$root_dir/rtl/camera/ov5640_cfg.v"         \
    "$root_dir/rtl/camera/ov5640_data.v"        \
    "$root_dir/rtl/camera/top_iic_copy.v"       \
    "$root_dir/rtl/camera/iic_shift_bit_copy.v" \
    "$root_dir/rtl/ddr3/ddr3_ctrl_2port.v"      \
    "$root_dir/rtl/ddr3/fifo_to_adapter.v"      \
    "$root_dir/rtl/ddr3/fifo_to_axi4.v"         \
    "$root_dir/rtl/ddr3/axi4_to_fifo.v"         \
    "$root_dir/rtl/freq_meter/freq_meter.v"     \
    "$root_dir/rtl/hdmi/hdmi_drvier.v"          \
    "$root_dir/rtl/hdmi/hdmi_i2c.v"             \
    "$root_dir/rtl/hdmi/hdmi_cfg.v"             \
    "$root_dir/rtl/hdmi/vga_ctrl.v"             \
    "$root_dir/rtl/xpm_cdc/xpm_rst_sync.v"      \
]

foreach f $rtl_files {
    if {[file exists $f]} {
        add_files -norecurse $f
    } else {
        puts "警告：找不到 $f"
    }
}
set_property top ov5640_ddr_hdmi [current_fileset]

#------------------------------------------------------------------------------
# 3) 约束文件
#------------------------------------------------------------------------------
foreach f [list \
    "$root_dir/constrs/ov5640_ddr3_hdmi_full_fixed.xdc" \
    "$root_dir/constrs/diag_cdc.xdc" ] {
    if {[file exists $f]} { add_files -fileset constrs_1 -norecurse $f }
}
set_property target_constrs_file \
    "$root_dir/constrs/ov5640_ddr3_hdmi_full_fixed.xdc" [current_fileset -constrset]

#------------------------------------------------------------------------------
# 4) IP（只加 .xci，输出产品由 Vivado 重新生成）
#------------------------------------------------------------------------------
set ip_files [list \
    "$root_dir/ip/clk_wiz_0/clk_wiz_0.xci"         \
    "$root_dir/ip/clk_wiz_1/clk_wiz_1.xci"         \
    "$root_dir/ip/mig_7series_0/mig_7series_0.xci" \
    "$root_dir/ip/wr_ddr3_fifo/wr_ddr3_fifo.xci"   \
    "$root_dir/ip/rd_ddr3_fifo/rd_ddr3_fifo.xci"   \
]

foreach f $ip_files {
    if {[file exists $f]} {
        add_files -norecurse $f
    } else {
        puts "警告：找不到 $f"
    }
}

if {[llength [get_ips -quiet]] > 0} {
    puts "正在生成 IP 输出产品，请稍候（MIG 较慢，约需几分钟）..."
    generate_target all [get_ips]
    # 若 IP 由旧版本 Vivado 创建，可取消下一行注释做升级
    # upgrade_ip [get_ips]
}

#------------------------------------------------------------------------------
# 5) 仿真文件（系统级 TB）
#------------------------------------------------------------------------------
set sim_tb "$root_dir/sim/tb_system.v"
if {[file exists $sim_tb]} {
    add_files -fileset sim_1 -norecurse $sim_tb
    set_property top tb_system [get_filesets sim_1]
}

#------------------------------------------------------------------------------
# 5b) 波形配置（可选，只含信号列表，不绑定任何仿真数据库）
#     必须在【仿真运行后】由波形窗口 File -> Open Waveform Configuration 载入。
#------------------------------------------------------------------------------
set wcfg "$root_dir/sim/tb_system_behav.wcfg"
if {[file exists $wcfg]} {
    if {[catch { add_files -fileset sim_1 -norecurse $wcfg } err]} {
        puts "提示：波形配置文件未加入工程（$err）"
        puts "      可在仿真运行后用 File -> Open Waveform Configuration 打开 $wcfg"
    }
}

#------------------------------------------------------------------------------
# 6) 可选：直接跑综合 / 实现（默认关闭）
#------------------------------------------------------------------------------
# launch_runs synth_1 -jobs 4
# wait_on_run synth_1
# launch_runs impl_1 -to_step write_bitstream -jobs 4
# wait_on_run impl_1

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "=================================================="
puts " 工程创建完成："
puts "   $root_dir/build/$proj_name/$proj_name.xpr"
puts ""
puts " 【上板前请确认】"
puts "   1) rtl/hdmi/vga_ctrl.v 里必须打开 `define Resolution_1280x720"
puts "      （仿真用的 Resolution_1280x2 上板会不出图）"
puts "   2) 顶层参数 COLOR_TEST 默认 0（正常显示）；置 1 输出 8 色竖彩条用于定位"
puts "   3) 首次生成 IP 后建议先 Run Synthesis 确认无误"
puts ""
puts " 【仿真】sim/tb_system.v 已加入 sim_1，顶层 tb_system；波形见 sim/tb_system_behav.wcfg"
puts "=================================================="
