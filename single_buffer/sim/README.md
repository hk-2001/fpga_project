# 仿真说明

## 目录里有什么

| 文件 | 说明 |
| --- | --- |
| `tb_top_link.v` | 链路级仿真顶层。摄像头数据 -> 写 FIFO -> fifo_to_axi4 -> MIG -> DDR3 -> 读回 -> 显示，整条通路跑一遍 |
| `tb_ddr3_link.v` | 只看 DDR3 这一段。跳过采集和显示，直接给 AXI4 发读写突发，用来单独验证 MIG 侧时序 |
| `ddr3_model.sv`<br>`ddr3_model_parameters.vh` | **这两个文件没有随仓库发布，需要自己下载，见下** |

## DDR3 仿真模型怎么来

`ddr3_model.sv` 用的是 Micron 官方的 DDR3 SDRAM 仿真模型（Verilog 版，常见于 `ddr3.v`）。文件头写着：

```
Copyright 2003 Micron Technology, Inc. All rights reserved.
```

Micron 的许可不允许二次分发，所以这个文件没有放进 Git 仓库——虽然它是跑仿真必需的一环。

拿到文件的几种途径，任选一种：

1. **Micron 官网**：搜 `Micron DDR3 SDRAM Verilog model`，在 MT41K / MT41J 系列颗粒页面下载仿真模型包，解压后找到 `ddr3.v` 和 `ddr3_parameters.vh`
2. **Vivado 安装目录**：MIG 生成的 example design 里有时会带一份，搜一下 `<Vivado安装路径>/data/.../ddr3_model`
3. **开发板资料**：部分板卡厂商的例程包里有

下载后按下面的名字放进 `sim/` 目录，跟 tb 放同级：

```
sim/
├── tb_top_link.v
├── tb_ddr3_link.v
├── ddr3_model.sv                 <- 放这里
└── ddr3_model_parameters.vh      <- 放这里
```

如果下载下来的文件名是 `ddr3.v` / `ddr3_parameters.vh`，改成上面这两个名字就行，tb 里例化的模块名是 `ddr3_model`。参数文件不需要改，tb 会直接 `include` 目录里的名字；若你手上的版本文件名不同，把 `ddr3_model.sv` 里的 include 行改一下即可。

## 怎么跑

Vivado 里建仿真源文件集，把 `sim/` 下这几个文件一起加进去（`sim_1`），顶层选 `tb_top_link`，直接 Run Simulation。

如果只想看 DDR3 那段，顶层选 `tb_ddr3_link`，跑得快一些。

`wave_link.wdb` 是抓好的波形数据库，9MB 多，太大没入库，本地看波形的话还在原位置。

## 注意

DVP 接口的摄像头部分（`ov5640_data`）在仿真里是用 tb 喂数据的，不接真实摄像头时序。SCCB / DDC 这两条 I2C 配置通路也不在仿真范围内——它们是一次性上电配置，用 ILA 抓实际波形更直接，截图在 `DEBUG/` 下面。
