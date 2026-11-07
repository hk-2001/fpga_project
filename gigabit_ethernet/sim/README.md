# 仿真说明

## 目录里有什么

| 文件 | 说明 |
| --- | --- |
| `tb_eth_top.v` | 全栈链路级仿真顶层：ARP / ICMP / UDP 请求进来，检查应答帧内容、字节序、FCS 与帧间隔 |
| `tb_rgmii.v` | 只跑 RGMII ↔ GMII 双向转换，检查 DDR 半字节不错位 |
| `tb_crc32_d8.v` | CRC-32 自检（`CBF43926`）、好帧 / 坏帧判别 |
| `tb_mac_rx.v` | 帧定界、MAC 头提取、字节序、FCS |
| `tb_ip_rx.v` | IP 字节序、首部校验和、`ip_ok` |
| `tb_arp_rx.v` | ARP 解析 + 缓存 + 应答，含 64 字节最小帧长 |
| `tb_icmp.v` | Echo 应答帧长、type=0、校验和修正 |
| `tb_udp.v` | UDP 端口互换、端口 5000 回显 |
| `tb_tx_arbiter.v` | 三路仲裁优先级 ARP > ICMP > UDP |
| `tb_preamble_inserter.v` | 前导码 `55×7` + `D5`、长度 `N+8`、数据无损 |
| `tb_tx_ifg.v` | 背靠背两帧各自完整、`IFG_HOLD=20` 拍空闲 |
| `tb_icmp_large.v` | 200 字节大包，XPM FIFO 回读无损 |
| `tb_sync_fifo.v` | FWFT 顺序、空满、`clr` |
| `xilinx_prims_sim.v`<br>`xpm_fifo_sync_sim.v`<br>`xpm_cdc_async_rst_sim.v` | IDDR/ODDR 与 XPM 原语的行为模型，iverilog 下替代器件库 |

一共 13 个自检查 testbench，全部随仓库发布，没有需要另外下载的第三方模型。

## 怎么跑

### iverilog（逐个用例）

```powershell
cd <本仓库目录>
$src = (Get-ChildItem -Recurse -Filter *.v -Path rtl,sim | ForEach-Object FullName)
iverilog -g2012 -o tb_eth_top.vvp -s tb_eth_top $src
vvp tb_eth_top.vvp
```

把 `-s` 和输出文件名换成对应 tb 就能逐个跑。13 个用例都是自检查，通过时打印 PASS，失败会显式报错。本地另有一键脚本依次运行全部用例，末行汇总 `PASS = 13, FAIL/异常 = 0`，不随本仓库发布。

### Vivado xsim

建仿真源文件集，把 `sim/` 下全部 `.v` 加进 `sim_1`，顶层选 `tb_eth_top`，直接 Run Simulation。只想看 RGMII 那段就把顶层换成 `tb_rgmii`，跑得快一些。

`create_project.tcl` 已经把这 16 个文件加进了 `sim_1`，并把仿真顶层设成 `tb_eth_top`。

## 注意

- `xilinx_prims_sim.v` 里的 MMCM 用输入时钟的延迟副本建模，反馈输出与输入同频，`CLKOUT0` / `CLKOUT1` 的周期由 VCO 周期与分频参数算出，相位按「周期 × PHASE / 360」换算成延时。它保证输出与输入相位锁定，但不是精确的器件时序模型。
- 行为模型里主时钟和 `rxc` 同源同相，采样必然正确。源同步相位问题（采样沿是否落在数据眼中央）仿真覆盖不到，只能靠上板 ILA 定位，截图在 `DEBUG/ila_waveform/` 下面。
- `xpm_fifo_sync_sim.v` / `xpm_cdc_async_rst_sim.v` 是简化行为模型，只覆盖本工程用到的接口与复位行为。
- PHY 的 RGMII-ID 由硬件默认配置提供，工程没有 MDIO 配置通路，这部分不在仿真范围内。
