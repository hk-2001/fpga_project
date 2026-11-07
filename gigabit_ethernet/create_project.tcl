#==============================================================================
# create_project.tcl —— 一键重建 Vivado 工程
#
# 用法（Vivado 2018.3）：
#   1. 打开 Vivado Tcl Console，cd 到这个脚本所在目录
#   2. source create_project.tcl
#   或者命令行：
#      vivado -mode batch -source create_project.tcl
#
# 说明：
#   - 器件：xc7a200tfbg484-2L（Artix-7 200T，野火升腾Pro）
#   - 路径用 [file dirname [info script]] 动态推导，仓库放哪个目录都能跑
#   - 本工程零 IP 文件依赖：MMCME2_BASE / xpm_fifo_sync / xpm_cdc_async_rst
#     都是直接例化的原语，不需要 .xci，也不需要 generate_target
#   - 约束分两份：eth_top_full.xdc 是引脚/时钟/IO 延迟/ILA 调试核，
#     diag_cdc.xdc 单独处理 RGMII 接收侧跨域路径，加载顺序不能反
#==============================================================================

set proj_name "eth_top"
set root_dir  [file normalize [file dirname [info script]]]
set part      "xc7a200tfbg484-2L"

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
# 2) RTL 源文件（17 个，按模块目录组织）
#------------------------------------------------------------------------------
set rtl_files [list \
    "$root_dir/rtl/top/eth_top.v"                \
    "$root_dir/rtl/phy/rgmii_to_gmii.v"          \
    "$root_dir/rtl/phy/gmii_to_rgmii.v"          \
    "$root_dir/rtl/phy/preamble_inserter.v"      \
    "$root_dir/rtl/common/clk_gen.v"             \
    "$root_dir/rtl/common/crc32_d8.v"            \
    "$root_dir/rtl/common/sync_fifo.v"           \
    "$root_dir/rtl/mac/mac_rx.v"                 \
    "$root_dir/rtl/arp/arp_rx.v"                 \
    "$root_dir/rtl/arp/arp_cache.v"              \
    "$root_dir/rtl/arp/arp_tx.v"                 \
    "$root_dir/rtl/ip/ip_rx.v"                   \
    "$root_dir/rtl/icmp/icmp_rx.v"               \
    "$root_dir/rtl/icmp/icmp_tx.v"               \
    "$root_dir/rtl/udp/udp_rx.v"                 \
    "$root_dir/rtl/udp/udp_tx.v"                 \
    "$root_dir/rtl/arbiter/tx_arbiter.v"         \
]

foreach f $rtl_files {
    if {[file exists $f]} { add_files -norecurse $f } else { puts "WARNING: missing $f" }
}
set_property top eth_top [current_fileset]

#------------------------------------------------------------------------------
# 3) 约束文件（主约束在前，CDC 约束在后）
#------------------------------------------------------------------------------
foreach f [list \
    "$root_dir/constrs/eth_top_full.xdc" \
    "$root_dir/constrs/diag_cdc.xdc" ] {
    if {[file exists $f]} { add_files -fileset constrs_1 -norecurse $f }
}
set_property target_constrs_file \
    "$root_dir/constrs/eth_top_full.xdc" [current_fileset -constrset]

#------------------------------------------------------------------------------
# 4) IP（本工程零 IP 依赖，ip/ 目录预留）
#------------------------------------------------------------------------------
# 若后续加入 .xci，在这里 add_files 并打开下面的 generate_target：
# foreach f [glob -nocomplain "$root_dir/ip/*/*.xci"] { add_files -norecurse $f }
# if {[llength [get_ips -quiet]] > 0} { generate_target all [get_ips] }

#------------------------------------------------------------------------------
# 5) 仿真文件（13 个 testbench + 3 个行为模型）
#------------------------------------------------------------------------------
set sim_files [list \
    "$root_dir/sim/tb_eth_top.v"                    \
    "$root_dir/sim/tb_rgmii.v"                      \
    "$root_dir/sim/tb_crc32_d8.v"                   \
    "$root_dir/sim/tb_mac_rx.v"                     \
    "$root_dir/sim/tb_ip_rx.v"                      \
    "$root_dir/sim/tb_arp_rx.v"                     \
    "$root_dir/sim/tb_icmp.v"                       \
    "$root_dir/sim/tb_udp.v"                        \
    "$root_dir/sim/tb_tx_arbiter.v"                 \
    "$root_dir/sim/tb_preamble_inserter.v"          \
    "$root_dir/sim/tb_tx_ifg.v"                     \
    "$root_dir/sim/tb_icmp_large.v"                 \
    "$root_dir/sim/tb_sync_fifo.v"                  \
    "$root_dir/sim/xilinx_prims_sim.v"              \
    "$root_dir/sim/xpm_fifo_sync_sim.v"             \
    "$root_dir/sim/xpm_cdc_async_rst_sim.v"         \
]

foreach f $sim_files {
    if {[file exists $f]} { add_files -fileset sim_1 -norecurse $f } else { puts "WARNING: missing $f" }
}
set_property top tb_eth_top [get_filesets sim_1]

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
puts " 上板前确认："
puts "   eth_top.v 里 SCAN_EN=0、IDELAY_TAP=5'd20（本板实测值）"
puts "   换板卡或换 PHY 时把 SCAN_EN 改回 1 重新扫描 RX 相位"
puts "=================================================="
