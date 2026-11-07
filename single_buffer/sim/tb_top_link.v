`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// 文件名 : tb_top_link.v
// 功  能 : 摄像头 -> DDR3 -> HDMI 全链路仿真（无任何打印，结果全部看波形）
//
// 验证链路：
//   TB 里的摄像头模型(VSYNC/HREF/DATA)
//     -> ov5640_top / ov5640_data（8bit 两拍拼成 16bit RGB565）
//     -> wr_ddr3_fifo -> fifo_to_axi4 -> MIG(AXI4) -> DDR3 颗粒(ddr3_model)
//     -> axi4_to_fifo -> rd_ddr3_fifo -> vga_ctrl -> hdmi_out_rgb
//
// 判定方法：
//   摄像头送进去的像素是已知图案，HDMI 输出端逐像素比对，
//   err_cnt == 0 且 chk_cnt 数到 CHK_PIX  => 全链路数据正确。
//
// 使用方法：
//   1) 把本文件加进 Simulation Sources（sim_1）
//      （ddr3_model.sv / ddr3_model_parameters.vh 已在同目录，不用再加）
//   2) Settings -> Simulation -> Simulation top module name : tb_top_link
//   3) Run Simulation -> Run Behavioral Simulation
//      仿真跑完自动结束，全程不打印任何信息。
////////////////////////////////////////////////////////////////////////////////

module tb_top_link;

//==============================================================================
// 1) 参数
//==============================================================================
    // ---- 仿真用的小画面（真实工程是 1280 x 720，改回即可，只是仿真会久很多）----
    parameter   CAM_W           = 128                   ;   // 每行像素
    parameter   CAM_H           = 8                     ;   // 行数
    parameter   FRAME_PIX       = CAM_W * CAM_H         ;   // 一帧像素数 = 1024
    parameter   CHK_PIX         = 2 * FRAME_PIX         ;   // 要核对的像素数 = 2048

    // ---- 时钟周期(ns) ----
    parameter   T_SYS           = 20.0                  ;   // 50MHz   板载晶振 -> clk_wiz_0
    parameter   T_PCLK          = 20.0                  ;   // 50MHz   摄像头像素时钟

    // ---- 摄像头时序(pclk 个数) ----
    parameter   CAM_VSYNC_W     = 8                     ;   // VSYNC 高电平宽度
    parameter   CAM_H_BLANK     = 20                    ;   // 行消隐
    parameter   CAM_V_BLANK     = 200                   ;   // 场消隐

    // ---- 仿真加速：I2C(SCCB/DDC) 速率 100k -> 5M，否则 251 个寄存器要配 90ms ----
    parameter   I2C_SPEEDUP     = 5000000               ;

    // ---- 超时时间(ns) ----
    parameter   RST_TIME        = 1000                  ;   // 复位保持
    parameter   INIT_TIMEOUT    = 10000000              ;   // 10ms  等 DDR3 初始化
    parameter   SHOW_TIMEOUT    = 20000000              ;   // 20ms  等 HDMI 出图
    parameter   CHK_TIMEOUT     = 5000000               ;   // 5ms   等比对完成
    parameter   ALL_TIMEOUT     = 60000000              ;   // 60ms  整体

//==============================================================================
// 2) 信号
//==============================================================================
    // ---- 送给 DUT 的输入 ----
    reg                             sys_clk             ;
    reg                             sys_rst_n           ;
    reg                             cam1_pclk           ;
    reg                             cam1_vsync          ;
    reg                             cam1_href           ;
    reg     [   7: 0]               cam1_data           ;

    // ---- I2C 开漏总线（不接从机也不会卡死：两个 I2C 主机的 ACK 检查都被注释了）----
    wire                            sccb1_scl           ;   // 摄像头 SCCB
    wire                            sccb1_sda           ;
    wire                            ddc_scl             ;   // HDMI   DDC
    wire                            ddc_sda             ;

    // ---- HDMI 输出 ----
    wire                            hdmi_out_clk        ;
    wire                            hdmi_out_rst_n      ;
    wire                            hdmi_out_hsync      ;
    wire                            hdmi_out_vsync      ;
    wire    [  23: 0]               hdmi_out_rgb        ;
    wire                            hdmi_out_de         ;

    // ---- DDR3 物理接口 ----
    wire    [  31: 0]               ddr3_dq             ;
    wire    [   3: 0]               ddr3_dqs_n          ;
    wire    [   3: 0]               ddr3_dqs_p          ;
    wire    [  14: 0]               ddr3_addr           ;
    wire    [   2: 0]               ddr3_ba             ;
    wire                            ddr3_ras_n          ;
    wire                            ddr3_cas_n          ;
    wire                            ddr3_we_n           ;
    wire                            ddr3_reset_n        ;
    wire    [   0: 0]               ddr3_ck_p           ;
    wire    [   0: 0]               ddr3_ck_n           ;
    wire    [   0: 0]               ddr3_cke            ;
    wire    [   0: 0]               ddr3_cs_n           ;
    wire    [   3: 0]               ddr3_dm             ;
    wire    [   0: 0]               ddr3_odt            ;

    // ---- 测试状态（结果都在这里，看波形即可）----
    reg                             ddr3_rst_n          ;   // 给 force 用，低有效
    reg                             chk_en              ;   // 比对使能
    reg     [  31: 0]               chk_cnt             ;   // 已比对像素数
    integer                         err_cnt             ;   // 错误像素数
    reg                             init_done_ok        ;   // DDR3 初始化完成
    reg                             cam_cfg_ok          ;   // 摄像头配置完成
    reg                             w_done_ok           ;   // 整帧写进 DDR3
    reg                             disp_started        ;   // HDMI 开始出图
    reg                             test_done           ;
    reg                             tb_pass             ;
    reg                             tb_fail             ;

    integer                         row                 ;
    integer                         col                 ;
    reg     [  15: 0]               pix16               ;

//==============================================================================
// 3) 时钟与复位
//==============================================================================
    initial begin
        sys_clk = 1'b0;
        forever #(T_SYS/2.0)  sys_clk  = ~sys_clk;
    end

    initial begin
        cam1_pclk = 1'b0;
        forever #(T_PCLK/2.0) cam1_pclk = ~cam1_pclk;
    end

    initial begin
        sys_rst_n  = 1'b0;
        ddr3_rst_n = 1'b0;
        #RST_TIME;
        sys_rst_n  = 1'b1;      // 系统复位释放
        #RST_TIME;
        ddr3_rst_n = 1'b1;      // DDR3 复位释放（低有效）
    end

//==============================================================================
// 4) 仿真专用调整（用 defparam / force 完成，不动工程源文件）
//==============================================================================
    // 4.1 把一帧缩小成 CAM_W x CAM_H，减少仿真时间
    //     （真实场景把 CAM_W/CAM_H 改回 1280/720 即可）
    defparam u_top.ddr3_ctrl_2port_inst.IMAGE_WIDTH  = CAM_W;
    defparam u_top.ddr3_ctrl_2port_inst.IMAGE_HEIGHT = CAM_H;

    // 4.2 提高 SCCB / DDC 速率，缩短 251 个摄像头寄存器的配置时间
    defparam u_top.ov5640_top_inst.top_iic_copy_inst.u_iic_shift_bit_copy.I2CLK = I2C_SPEEDUP;
    defparam u_top.hdmi_drvier_inst.hdmi_i2c_inst.top_iic_copy_inst.u_iic_shift_bit_copy.I2CLK = I2C_SPEEDUP;

    // 4.3 顶层 ov5640_ddr_hdmi.v 里 .ddr3_rst((~sys_rst_n)|(~locked)) 是高有效，
    //     而 MIG 的 sys_rst 是低有效（RST_ACT_LOW=1），这样接 DDR3 永远不初始化。
    //     这里用 force 在仿真里纠正极性；上板前请把顶层改成 .ddr3_rst(sys_rst_n & locked)
    initial force u_top.ddr3_ctrl_2port_inst.ddr3_rst = ddr3_rst_n;

//==============================================================================
// 5) DUT：工程顶层
//==============================================================================
    ov5640_ddr_hdmi u_top
    (
        .sys_clk                    (sys_clk            ),
        .sys_rst_n                  (sys_rst_n          ),

        .cam_rst_n                  (                   ),
        .cam_pwdn                   (                   ),

        .cam1_pclk                  (cam1_pclk          ),
        .cam1_vsync                 (cam1_vsync         ),
        .cam1_href                  (cam1_href          ),
        .cam1_data                  (cam1_data          ),
        .sccb1_scl                  (sccb1_scl          ),
        .sccb1_sda                  (sccb1_sda          ),

        .ddc_scl                    (ddc_scl            ),
        .ddc_sda                    (ddc_sda            ),
        .hdmi_out_clk               (hdmi_out_clk       ),
        .hdmi_out_rst_n             (hdmi_out_rst_n     ),
        .hdmi_out_hsync             (hdmi_out_hsync     ),
        .hdmi_out_vsync             (hdmi_out_vsync     ),
        .hdmi_out_rgb               (hdmi_out_rgb       ),
        .hdmi_out_de                (hdmi_out_de        ),

        .ddr3_dq                    (ddr3_dq            ),
        .ddr3_dqs_n                 (ddr3_dqs_n         ),
        .ddr3_dqs_p                 (ddr3_dqs_p         ),
        .ddr3_addr                  (ddr3_addr          ),
        .ddr3_ba                    (ddr3_ba            ),
        .ddr3_ras_n                 (ddr3_ras_n         ),
        .ddr3_cas_n                 (ddr3_cas_n         ),
        .ddr3_we_n                  (ddr3_we_n          ),
        .ddr3_reset_n               (ddr3_reset_n       ),
        .ddr3_ck_p                  (ddr3_ck_p          ),
        .ddr3_ck_n                  (ddr3_ck_n          ),
        .ddr3_cke                   (ddr3_cke           ),
        .ddr3_cs_n                  (ddr3_cs_n          ),
        .ddr3_dm                    (ddr3_dm            ),
        .ddr3_odt                   (ddr3_odt           )
    );

//==============================================================================
// 6) DDR3 颗粒模型：32bit DQ = 2 片 x16
//==============================================================================
    genvar i;
    generate
        for (i = 0; i < 2; i = i + 1) begin : gen_ddr3_model
            ddr3_model u_ddr3_model
            (
                .rst_n              (ddr3_reset_n       ),
                .ck                 (ddr3_ck_p          ),
                .ck_n               (ddr3_ck_n          ),
                .cke                (ddr3_cke[0]        ),
                .cs_n               (ddr3_cs_n[0]       ),
                .ras_n              (ddr3_ras_n         ),
                .cas_n              (ddr3_cas_n         ),
                .we_n               (ddr3_we_n          ),
                .dm_tdqs            (ddr3_dm[2*i +: 2]  ),
                .ba                 (ddr3_ba            ),
                .addr               (ddr3_addr          ),
                .dq                 (ddr3_dq[16*i +: 16]),
                .dqs                (ddr3_dqs_p[2*i +: 2]),
                .dqs_n              (ddr3_dqs_n[2*i +: 2]),
                .tdqs_n             (                   ),
                .odt                (ddr3_odt[0]        )
            );
        end
    endgenerate

//==============================================================================
// 7) 数据图案
//==============================================================================
    // 摄像头第 idx 个像素的 RGB565 值
    function [15:0] pixel;
        input [31:0] idx;
        begin
            pixel = idx[15:0] ^ 16'hA5A5;
        end
    endfunction

    // RGB565 -> RGB888，与 ov5640_ddr_hdmi.v 顶层的填充方式完全一致
    function [23:0] rgb888;
        input [15:0] p;  
        begin
            rgb888 = {p[15:11], p[15:13],
                      p[10:5],  p[10:9],
                      p[ 4:0],  p[ 4:2]};
        end
    endfunction

//==============================================================================
// 8) 摄像头模型：OV5640 的 VSYNC / HREF / DATA 时序
//    8bit 数据口，2 个 pclk 传一个像素（先高字节后低字节）
//    所有信号都在 pclk 下降沿更新，避开和 DUT 的采样竞争
//==============================================================================
    initial begin
        cam1_vsync = 1'b0;
        cam1_href  = 1'b0;
        cam1_data  = 8'h0;
        @(negedge cam1_pclk);

        forever begin
            // ---- 场同步脉冲 ----
            cam1_vsync = 1'b1;
            cam1_href  = 1'b0;
            repeat (CAM_VSYNC_W) @(negedge cam1_pclk);
            cam1_vsync = 1'b0;
            repeat (CAM_V_BLANK) @(negedge cam1_pclk);

            // ---- 有效行 ----
            for (row = 0; row < CAM_H; row = row + 1) begin
                cam1_href = 1'b1;
                for (col = 0; col < CAM_W; col = col + 1) begin
                    pix16     = pixel(row * CAM_W + col);
                    cam1_data = pix16[15:8];            // 高字节
                    @(negedge cam1_pclk);
                    cam1_data = pix16[ 7:0];            // 低字节
                    @(negedge cam1_pclk);
                end
                cam1_href = 1'b0;
                repeat (CAM_H_BLANK) @(negedge cam1_pclk);
            end

            repeat (CAM_V_BLANK) @(negedge cam1_pclk);
        end
    end

//==============================================================================
// 9) HDMI 输出比对
//    读 FIFO 是 Standard FIFO：rd_en 后一拍数据才有效，
//    vga_ctrl 已经提前一拍发请求，所以 rgb_valid(de) 为高时 hdmi_out_rgb 就是有效像素。
//    DDR3 里只有一帧 1024 个像素，读通道会循环重复读，所以期望值取 (索引 % 1024)。
//==============================================================================
    always @(posedge hdmi_out_clk) begin
        if (chk_en && hdmi_out_de) begin
            if (hdmi_out_rgb !== rgb888(pixel(chk_cnt % FRAME_PIX)))
                err_cnt <= err_cnt + 1;
            chk_cnt <= chk_cnt + 1'b1;
        end
    end

//==============================================================================
// 10) 关键节点指示（看波形用，一级一级确认链路走到哪一步）
//==============================================================================
    always @(posedge u_top.ui_clk) begin
        if (u_top.ddr3_init_done) init_done_ok <= 1'b1;    // DDR3 初始化 + 校准完成
        if (u_top.cam_cfg_done  ) cam_cfg_ok   <= 1'b1;    // 摄像头寄存器配置完成
        if (u_top.camera_done   ) w_done_ok    <= 1'b1;    // 整帧写进 DDR3
    end

    always @(posedge hdmi_out_clk) begin
        if (u_top.hdmi_drvier_inst.vga_ctrl_inst.display_started)
            disp_started <= 1'b1;                          // HDMI 开始出图
    end

//==============================================================================
// 11) 主流程
//==============================================================================
    initial begin
        err_cnt      = 0;
        chk_cnt      = 0;
        chk_en       = 1'b0;
        test_done    = 1'b0;
        tb_pass      = 1'b0;
        tb_fail      = 1'b0;
        init_done_ok = 1'b0;
        cam_cfg_ok   = 1'b0;
        w_done_ok    = 1'b0;
        disp_started = 1'b0;

        wait (sys_rst_n == 1'b1);
        wait (u_top.ddr3_init_done == 1'b1);                                    // ① DDR3 起来
        wait (u_top.hdmi_drvier_inst.vga_ctrl_inst.display_started == 1'b1);    // ② 开始出图

        chk_en = 1'b1;                                                          // ③ 开始比对
        wait (chk_cnt == CHK_PIX);
        #1000;
        chk_en = 1'b0;

        if (err_cnt == 0) tb_pass <= 1'b1; else tb_fail <= 1'b1;                // ④ 结论

        test_done = 1'b1;
        #1000;
        $finish;
    end

//==============================================================================
// 12) 超时看护
//==============================================================================
    initial begin
        #(2*RST_TIME + INIT_TIMEOUT);
        if (u_top.ddr3_init_done !== 1'b1) begin tb_fail = 1'b1; $finish; end
    end

    initial begin
        #(2*RST_TIME + SHOW_TIMEOUT);
        if (!disp_started) begin tb_fail = 1'b1; $finish; end
    end

    initial begin
        #(2*RST_TIME + SHOW_TIMEOUT + CHK_TIMEOUT);
        if (chk_cnt != CHK_PIX) begin tb_fail = 1'b1; $finish; end
    end

    initial begin
        #ALL_TIMEOUT;
        if (!test_done) begin tb_fail = 1'b1; $finish; end
    end

endmodule
