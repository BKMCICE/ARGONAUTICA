// H04T private top: GPIO status OUT uses SYS50; the original J capture/SoC stays unchanged.
// MES50HP board variant with the vendor DDR3 controller and cached RV32 SoC.
// DDR UI supplies the 100 MHz CPU clock, so cache and native DDR share a clock.
module pangu50k_capture_top #(
    parameter RAM_INIT_FILE="",
    parameter CAPTURE_W=1920,CAPTURE_H=1080,FIFO_ADDR_BITS=9,
    parameter FRONTEND_GEO_INTERVAL=50000,FRONTEND_HTOTAL=2200,FRONTEND_VTOTAL=1125
)(
    input  wire        sys_clk,
    input wire hdmi_rx_pixclk,hdmi_rx_de,hdmi_rx_hs,hdmi_rx_vs,
    input wire [7:0] hdmi_rx_r,hdmi_rx_g,hdmi_rx_b,
    output wire hdmi_rx_iic_scl,inout wire hdmi_rx_iic_sda,
    output wire [7:0]  led,
    input  wire        uart_rx,
    output wire        uart_tx,
    input wire flash_miso,
    output wire flash_cs_n,flash_sck,flash_mosi,flash_wp_n,flash_hold_n,
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

    wire ui_command_valid,ui_busy,ui_protocol_error,ui_result_valid;
    wire [23:0] ui_command;
    wire [2:0] ui_phase;wire [7:0] ui_count;wire [31:0] ui_ms;
    wire [79:0] ui_classes;wire [99:0] ui_scores;
    wire [26:0] capture_sample;
    wire capture_ready,capture_reset_n;
    wire diag_sys_reset_n;wire [511:0] diag_source,diag_data;
    wire diag_request,diag_busy,diag_valid,diag_timeout;wire [31:0] diag_sequence;
    hdmi_capture_frontend #(.GEO_INTERVAL_CYCLES(FRONTEND_GEO_INTERVAL),.EXPECT_W(CAPTURE_W),.EXPECT_H(CAPTURE_H),
        .EXPECT_HTOTAL(FRONTEND_HTOTAL),.EXPECT_VTOTAL(FRONTEND_VTOTAL),.ENABLE_RESULT_UI(1)) frontend(
        .result_valid(ui_result_valid),.result_phase(ui_phase),.result_count(ui_count),.result_ms(ui_ms),
        .result_classes(ui_classes),.result_scores(ui_scores),
        .sys_clk(sys_clk),.status_code(led),.sys_pll_ready(pll_lock),.hdmi_rx_pixclk(hdmi_rx_pixclk),.hdmi_rx_de(hdmi_rx_de),.hdmi_rx_hs(hdmi_rx_hs),.hdmi_rx_vs(hdmi_rx_vs),
        .hdmi_rx_r(hdmi_rx_r),.hdmi_rx_g(hdmi_rx_g),.hdmi_rx_b(hdmi_rx_b),
        .hdmi_rx_iic_scl(hdmi_rx_iic_scl),.hdmi_rx_iic_sda(hdmi_rx_iic_sda),
        .hdmi_rst_n(hdmi_rst_n),.hdmi_scl(hdmi_scl),.hdmi_sda(hdmi_sda),
        .hdmi_pclk(hdmi_pclk),.hdmi_vs(hdmi_vs),.hdmi_hs(hdmi_hs),.hdmi_de(hdmi_de),.hdmi_r(hdmi_r),.hdmi_g(hdmi_g),.hdmi_b(hdmi_b),
        .capture_sample(capture_sample),.capture_ready(capture_ready),.capture_reset_n(capture_reset_n),
        .diag_reset_n(diag_sys_reset_n),.diag_source(diag_source));

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
    hdmi_result_mailbox result_cdc(.ui_clk(ui_clk),.sys_clk(sys_clk),
        .reset_n(diag_sys_reset_n&&reset_sync[3]),.command_valid(ui_command_valid),.command(ui_command),
        .busy(ui_busy),.protocol_error(ui_protocol_error),.result_valid(ui_result_valid),
        .phase(ui_phase),.count(ui_count),.forward_ms(ui_ms),.classes(ui_classes),.scores(ui_scores));
    hdmi_frontend_snapshot status_cdc(
        .sys_clk(sys_clk),.ui_clk(ui_clk),.reset_n(diag_sys_reset_n&&reset_sync[3]),
        .source_data(diag_source),.request(diag_request),.busy(diag_busy),.valid(diag_valid),
        .timed_out(diag_timeout),.snapshot_sequence(diag_sequence),.data(diag_data));
    capture_soc_top #(.ENABLE_FLASH_BOOT(1),.ENABLE_RESULT_UI(1),.RAM_INIT_FILE(RAM_INIT_FILE),.CAPTURE_W(CAPTURE_W),.CAPTURE_H(CAPTURE_H),.FIFO_ADDR_BITS(FIFO_ADDR_BITS)) u_soc (
        .clk(ui_clk), .rst_n(reset_sync[3]), .ddr_init_done(ddr_init_done),
        .pix_clk(hdmi_rx_pixclk),.pix_reset_n(capture_reset_n),.capture_ready(capture_ready),.capture_sample(capture_sample),
        .diag_request(diag_request),.diag_busy(diag_busy),.diag_valid(diag_valid),.diag_timeout(diag_timeout),
        .diag_sequence(diag_sequence),.diag_data(diag_data),
        .ui_command_valid(ui_command_valid),.ui_command(ui_command),.ui_busy(ui_busy),.ui_protocol_error(ui_protocol_error),
        .flash_miso(flash_miso),.flash_cs_n(flash_cs_n),.flash_sck(flash_sck),
        .flash_mosi(flash_mosi),.flash_wp_n(flash_wp_n),.flash_hold_n(flash_hold_n),
        .uart_rxd(uart_rx), .uart_txd(uart_tx), .gpio_out(led), .gpio_in(8'hFF),
        .axi_awaddr(awaddr), .axi_awuser_ap(awap), .axi_awuser_id(awid),
        .axi_awlen(awlen), .axi_awready(awready), .axi_awvalid(awvalid),
        .axi_wdata(wdata), .axi_wstrb(wstrb), .axi_wready(wready),
        .axi_araddr(araddr), .axi_aruser_ap(arap), .axi_aruser_id(arid),
        .axi_arlen(arlen), .axi_arready(arready), .axi_arvalid(arvalid),
        .axi_rdata(rdata), .axi_rvalid(rvalid), .axi_rlast(rlast)
    );
endmodule
