#==============================================================================
# create_project.tcl —— 一键重建 Vivado 工程（替代已损坏的 .xpr）
#
# 用法（Vivado 2018.3）：
#   1. 打开 Vivado Tcl Console，cd 到本文件所在目录
#      cd E:/xxx/DEBUG_YSE
#   2. source create_project.tcl
#   或者命令行：
#      vivado -mode batch -source create_project.tcl
#
# 说明：
#   - 器件：xc7a200tfbg484-2（Artix-7 200T，与你原工程一致）
#   - rtl/camera 和 rtl/hdmi 下有两份同名模块（top_iic_copy.v / iic_shift_bit_copy.v），
#     本脚本只添加 camera 下的一份，否则会重复定义报错。
#     建议把这两个文件移到 rtl/common/ 后只保留一份。
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
# 1) 建工程
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
# 生成 IP 输出产品（可能要几分钟，MIG 比较慢）
if {[llength [get_ips -quiet]] > 0} {
    puts "正在生成 IP 输出产品，请稍候..."
    generate_target all [get_ips]
    # 若 IP 是旧版本创建的，可打开下面这行做升级
    # upgrade_ip [get_ips]
}

#------------------------------------------------------------------------------
# 5) 仿真文件
#------------------------------------------------------------------------------
foreach f [list \
    "$root_dir/sim/tb_top_link.v"             \
    "$root_dir/sim/ddr3_model.sv"             \
    "$root_dir/sim/ddr3_model_parameters.vh" ] {
    if {[file exists $f]} { add_files -fileset sim_1 -norecurse $f }
}
set_property top tb_top_link [get_filesets sim_1]

#------------------------------------------------------------------------------
# 6) 可选：直接跑综合/实现（默认注释掉）
#------------------------------------------------------------------------------
# launch_runs synth_1 -jobs 4
# wait_on_run synth_1
# launch_runs impl_1 -to_step write_bitstream -jobs 4
# wait_on_run impl_1

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "=================================================="
puts " 工程创建完成：$root_dir/build/$proj_name/$proj_name.xpr"
puts ""
puts " 【重要】上板前请确认："
puts "   rtl/hdmi/vga_ctrl.v 里必须打开 `define Resolution_1280x720"
puts "   （仿真用的 Resolution_1280x2 上板会不出图）"
puts "=================================================="
