// MES50HP board variant with the vendor DDR3 controller and cached RV32 SoC.
// DDR UI supplies the 100 MHz CPU clock, so cache and native DDR share a clock.
module pangu50k_ddr_top #(
    parameter RAM_INIT_FILE = "",
    parameter ENABLE_BTB = 1,
    parameter ENABLE_AI_BLOCK = 0,
    parameter ENABLE_AI_QUANT = 0,
    parameter ENABLE_AI_BLOCK8 = 0,
    parameter CACHE_STATS_SPLIT_COUNTERS = 0,
    parameter ICACHE_DRM = 0,
    parameter ICACHE_EARLY_READ = 0,
    parameter DCACHE_TAG_STORAGE = 0,
    parameter REGFILE_STORAGE = 0,
    parameter ENABLE_PIPELINE_PROBE = 0
)(
    input  wire        sys_clk,
    output wire [7:0]  led,
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire        hdmi_rst_n,
    output wire        hdmi_scl,
    inout  wire        hdmi_sda,
    output wire        hdmi_pclk,
    output wire        hdmi_vs,
    output wire        hdmi_hs,
    output wire        hdmi_de,
    output wire [7:0]  hdmi_r,
    output wire [7:0]  hdmi_g,
    output wire [7:0]  hdmi_b,
    output wire        mem_rst_n,
    output wire        mem_ck,
    output wire        mem_ck_n,
    output wire        mem_cke,
    output wire        mem_cs_n,
    output wire        mem_ras_n,
    output wire        mem_cas_n,
    output wire        mem_we_n,
    output wire        mem_odt,
    output wire [14:0] mem_a,
    output wire [2:0]  mem_ba,
    inout  wire [3:0]  mem_dqs,
    inout  wire [3:0]  mem_dqs_n,
    inout  wire [31:0] mem_dq,
    output wire [3:0]  mem_dm
);
    wire ui_clk, pll_lock, ddr_init_done;
    wire [27:0] awaddr, araddr;
    wire awap, arap, awvalid, arvalid, awready, arready, wready;
    wire [3:0] awid, arid, awlen, arlen;
    wire [255:0] wdata, rdata;
    wire [31:0] wstrb;
    wire rvalid, rlast;

    // The video registers stay on the constrained 50 MHz system clock.
    // Match the board's HDMI reference: data updates with the output PCLK
    // rising edge. MS7210 init writes PA clock inversion (0x1281=0x04), so
    // its input latch sees the opposite edge. External margin still needs
    // receiver setup/hold and board trace timing, then on-board validation.
    reg hdmi_pix_phase = 0;
    always @(posedge sys_clk) hdmi_pix_phase <= ~hdmi_pix_phase;
    assign hdmi_pclk = hdmi_pix_phase;
    wire hdmi_init_done, hdmi_init_error;
    ms7210_init u_hdmi_init (
        .clk(sys_clk), .rst_n(pll_lock),
        .hdmi_rst_n(hdmi_rst_n), .scl(hdmi_scl), .sda(hdmi_sda),
        .init_done(hdmi_init_done), .init_error(hdmi_init_error)
    );
    hdmi_status_video u_hdmi_video (
        .pix_clk(sys_clk), .pixel_enable(!hdmi_pix_phase),
        .rst_n(pll_lock && hdmi_init_done),
        .status_code(led), .hs(hdmi_hs), .vs(hdmi_vs), .de(hdmi_de),
        .r(hdmi_r), .g(hdmi_g), .b(hdmi_b)
    );

    wire ddr_reset_n;
    power_on_reset u_ddr_por (.clk(sys_clk), .rst_n(ddr_reset_n));
    ddr3_test u_ddr (
        .ref_clk(sys_clk), .resetn(ddr_reset_n),
        .ddr_init_done(ddr_init_done), .ddrphy_clkin(ui_clk), .pll_lock(pll_lock),
        .axi_awaddr(awaddr), .axi_awuser_ap(awap), .axi_awuser_id(awid),
        .axi_awlen(awlen), .axi_awready(awready), .axi_awvalid(awvalid),
        .axi_wdata(wdata), .axi_wstrb(wstrb), .axi_wready(wready),
        .axi_wusero_id(), .axi_wusero_last(),
        .axi_araddr(araddr), .axi_aruser_ap(arap), .axi_aruser_id(arid),
        .axi_arlen(arlen), .axi_arready(arready), .axi_arvalid(arvalid),
        .axi_rdata(rdata), .axi_rid(), .axi_rlast(rlast), .axi_rvalid(rvalid),
        .apb_clk(1'b0), .apb_rst_n(1'b0), .apb_sel(1'b0), .apb_enable(1'b0),
        .apb_addr(8'b0), .apb_write(1'b0), .apb_ready(),
        .apb_wdata(16'b0), .apb_rdata(), .apb_int(),
        .debug_data(), .debug_slice_state(), .debug_calib_ctrl(),
        .ck_dly_set_bin(), .force_ck_dly_en(1'b0), .force_ck_dly_set_bin(8'b0),
        .dll_step(), .dll_lock(), .init_read_clk_ctrl(2'b0), .init_slip_step(4'b0),
        .force_read_clk_ctrl(1'b0), .ddrphy_gate_update_en(1'b1),
        .update_com_val_err_flag(), .rd_fake_stop(1'b0),
        .mem_rst_n(mem_rst_n), .mem_ck(mem_ck), .mem_ck_n(mem_ck_n),
        .mem_cke(mem_cke), .mem_cs_n(mem_cs_n), .mem_ras_n(mem_ras_n),
        .mem_cas_n(mem_cas_n), .mem_we_n(mem_we_n), .mem_odt(mem_odt),
        .mem_a(mem_a), .mem_ba(mem_ba), .mem_dqs(mem_dqs), .mem_dqs_n(mem_dqs_n),
        .mem_dq(mem_dq), .mem_dm(mem_dm)
    );

    reg [3:0] reset_sync = 0;
    wire board_ready = pll_lock && ddr_init_done;
    always @(posedge ui_clk or negedge board_ready) begin
        if (!board_ready) reset_sync <= 0;
        else reset_sync <= {reset_sync[2:0], 1'b1};
    end
    soc_top_ddr #(.RAM_INIT_FILE(RAM_INIT_FILE), .ENABLE_BTB(ENABLE_BTB), .ENABLE_AI_BLOCK(ENABLE_AI_BLOCK), .ENABLE_AI_QUANT(ENABLE_AI_QUANT), .ENABLE_AI_BLOCK8(ENABLE_AI_BLOCK8), .CACHE_STATS_SPLIT_COUNTERS(CACHE_STATS_SPLIT_COUNTERS), .ICACHE_DRM(ICACHE_DRM), .ICACHE_EARLY_READ(ICACHE_EARLY_READ), .DCACHE_TAG_STORAGE(DCACHE_TAG_STORAGE), .REGFILE_STORAGE(REGFILE_STORAGE), .ENABLE_PIPELINE_PROBE(ENABLE_PIPELINE_PROBE)) u_soc (
        .clk(ui_clk), .rst_n(reset_sync[3]), .ddr_init_done(ddr_init_done),
        .uart_rxd(uart_rx), .uart_txd(uart_tx), .gpio_out(led), .gpio_in(8'hFF),
        .axi_awaddr(awaddr), .axi_awuser_ap(awap), .axi_awuser_id(awid),
        .axi_awlen(awlen), .axi_awready(awready), .axi_awvalid(awvalid),
        .axi_wdata(wdata), .axi_wstrb(wstrb), .axi_wready(wready),
        .axi_araddr(araddr), .axi_aruser_ap(arap), .axi_aruser_id(arid),
        .axi_arlen(arlen), .axi_arready(arready), .axi_arvalid(arvalid),
        .axi_rdata(rdata), .axi_rvalid(rvalid), .axi_rlast(rlast)
    );
endmodule
