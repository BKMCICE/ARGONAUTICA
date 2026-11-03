// RV32 SoC with 64 KiB boot TCM and cached DDR3 window at 0x8000_0000.
// clk is the DDR controller's 100 MHz UI clock; no CPU/DDR clock crossing.
module soc_top_ddr #(
    parameter RAM_INIT_FILE = "",
    parameter ENABLE_BTB = 1,
    parameter ENABLE_AI_BLOCK = 0,
    parameter ENABLE_AI_WINDOW = 0,
    parameter ENABLE_AI_QUANT = 0,
    parameter ENABLE_AI_BLOCK8 = 0,
    parameter CACHE_STATS_SPLIT_COUNTERS = 0,
    parameter ICACHE_DRM = 0,
    parameter ICACHE_EARLY_READ = 0,
    parameter DCACHE_TAG_STORAGE = 0,
    parameter REGFILE_STORAGE = 0,
    parameter ENABLE_PIPELINE_PROBE = 0
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         ddr_init_done,
    input  wire         uart_rxd,
    output wire         uart_txd,
    output wire [7:0]   gpio_out,
    input  wire [7:0]   gpio_in,
    output wire [27:0]  axi_awaddr,
    output wire         axi_awuser_ap,
    output wire [3:0]   axi_awuser_id,
    output wire [3:0]   axi_awlen,
    input  wire         axi_awready,
    output wire         axi_awvalid,
    output wire [255:0] axi_wdata,
    output wire [31:0]  axi_wstrb,
    input  wire         axi_wready,
    output wire [27:0]  axi_araddr,
    output wire         axi_aruser_ap,
    output wire [3:0]   axi_aruser_id,
    output wire [3:0]   axi_arlen,
    input  wire         axi_arready,
    output wire         axi_arvalid,
    input  wire [255:0] axi_rdata,
    input  wire         axi_rvalid,
    input  wire         axi_rlast
);
    wire imem_req, imem_ready, imem_fault, dmem_req, dmem_we, dmem_ready, dmem_fault;
    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0] dmem_be;
    wire irq_sw, irq_tim, irq_ext;
    wire ev_ret, ev_br, ev_mp, ev_lu, ev_is, ev_ds, ev_tr;
    wire fetch_flush, fencei_req, fencei_done;
    rv_core #(.ENABLE_M(1), .ENABLE_BTB(ENABLE_BTB), .ENABLE_CACHE_FENCE(1), .REGFILE_STORAGE(REGFILE_STORAGE), .ENABLE_PIPELINE_PROBE(ENABLE_PIPELINE_PROBE)) u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_req(imem_req), .imem_addr(imem_addr), .imem_rdata(imem_rdata), .imem_ready(imem_ready), .imem_fault(imem_fault),
        .dmem_req(dmem_req), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready), .dmem_fault(dmem_fault),
        .irq_software(irq_sw), .irq_timer(irq_tim), .irq_external(irq_ext),
        .ev_instr_retired(ev_ret), .ev_branch(ev_br), .ev_branch_mispred(ev_mp),
        .ev_load_use_stall(ev_lu), .ev_imem_stall(ev_is), .ev_dmem_stall(ev_ds),
        .ev_trap(ev_tr), .fetch_flush(fetch_flush),
        .fencei_req(fencei_req), .fencei_done(fencei_done)
    );

    wire i_ddr = imem_addr[31:30] == 2'b10;
    // The PC may already point across the TCM/DDR boundary after BTB
    // prediction while the preceding request is still in flight. Select
    // its response using the domain captured with that request.
    reg i_response_ddr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) i_response_ddr <= 1'b0;
        else if (imem_req) i_response_ddr <= i_ddr;
    end
    wire boot_i_ready, boot_i_fault, cache_i_ready;
    wire [31:0] boot_i_rdata, cache_i_rdata;
    assign imem_ready = i_response_ddr ? cache_i_ready : boot_i_ready;
    assign imem_fault = i_response_ddr ? 1'b0 : boot_i_fault;
    assign imem_rdata = i_response_ddr ? cache_i_rdata : boot_i_rdata;

    localparam S_RAM = 0, S_DDR = 1, S_UART = 2, S_GPIO = 3, S_CLINT = 4, S_PERF = 5, S_AI = 6, S_CACHE_STATS = 7;
    localparam NS = 8;
    wire [NS-1:0] sel, s_req, s_ready;
    wire [NS*32-1:0] s_rdata;
    wire s_we;
    wire [3:0] s_be;
    wire [31:0] s_addr, s_wdata;
    assign sel[S_RAM] = dmem_addr[31:16] == 0;
    assign sel[S_DDR] = dmem_addr[31:30] == 2'b10;
    assign sel[S_UART] = dmem_addr[31:12] == 20'h40000;
    assign sel[S_GPIO] = dmem_addr[31:12] == 20'h40001;
    assign sel[S_CLINT] = dmem_addr[31:12] == 20'h40002;
    assign sel[S_PERF] = dmem_addr[31:12] == 20'h40003;
    assign sel[S_AI] = dmem_addr[31:12] == 20'h40004;
    assign sel[S_CACHE_STATS] = dmem_addr[31:12] == 20'h40005;
    // The eight address windows above are mutually exclusive.
    soc_bus #(.N_SLAVES(NS), .ONE_HOT_SELECT(1)) u_bus (
        .m_req(dmem_req), .m_we(dmem_we), .m_be(dmem_be), .m_addr(dmem_addr), .m_wdata(dmem_wdata),
        .m_rdata(dmem_rdata), .m_ready(dmem_ready), .m_fault(dmem_fault), .sel(sel),
        .s_req(s_req), .s_we(s_we), .s_be(s_be), .s_addr(s_addr), .s_wdata(s_wdata),
        .s_rdata(s_rdata), .s_ready(s_ready)
    );
    soc_ram #(.ADDR_WIDTH(14), .INIT_FILE(RAM_INIT_FILE)) u_boot_ram (
        .clk(clk), .rst_n(rst_n),
        .i_req(imem_req && !i_ddr), .i_addr(imem_addr), .i_rdata(boot_i_rdata), .i_ready(boot_i_ready), .i_fault(boot_i_fault),
        .d_req(s_req[S_RAM]), .d_we(s_we), .d_be(s_be), .d_addr(s_addr), .d_wdata(s_wdata),
        .d_rdata(s_rdata[S_RAM*32 +: 32]), .d_ready(s_ready[S_RAM])
    );

    wire cache_i_req, cache_i_word_ready;
    wire [31:0] cache_i_addr, cache_i_word;
    imem_cache_adapter u_if_adapter (
        .clk(clk), .rst_n(rst_n), .flush(fetch_flush),
        .core_req(imem_req && i_ddr), .core_addr(imem_addr),
        .core_rdata(cache_i_rdata), .core_ready(cache_i_ready),
        .cache_req(cache_i_req), .cache_addr(cache_i_addr),
        .cache_rdata(cache_i_word), .cache_ready(cache_i_word_ready)
    );
    wire il_req, il_we, il_ready, dl_req, dl_we, dl_ready;
    wire i_hit, i_miss, d_hit, d_miss;
    wire [31:0] il_addr, dl_addr;
    wire [255:0] il_wdata, il_rdata, dl_wdata, dl_rdata;
    generate if (ICACHE_DRM == 1) begin : drm_icache
        rv_icache_drm #(.EARLY_READ(ICACHE_EARLY_READ)) u_icache (
            .clk(clk), .rst_n(rst_n), .invalidate(fencei_done), .flush_req(1'b0), .flush_done(),
            .cpu_req(cache_i_req), .cpu_addr(cache_i_addr),
            .cpu_rdata(cache_i_word), .cpu_ready(cache_i_word_ready),
            .hit_event(i_hit), .miss_event(i_miss),
            .line_req(il_req), .line_we(il_we), .line_addr(il_addr),
            .line_wdata(il_wdata), .line_rdata(il_rdata), .line_ready(il_ready)
        );
    end else begin : original_icache
    rv_cache_2way u_icache (
        .clk(clk), .rst_n(rst_n), .invalidate(fencei_done), .flush_req(1'b0), .flush_done(),
        .cpu_req(cache_i_req), .cpu_we(1'b0), .cpu_be(4'b0),
        .cpu_addr(cache_i_addr), .cpu_wdata(32'b0),
        .cpu_rdata(cache_i_word), .cpu_ready(cache_i_word_ready),
        .hit_event(i_hit), .miss_event(i_miss),
        .line_req(il_req), .line_we(il_we), .line_addr(il_addr),
        .line_wdata(il_wdata), .line_rdata(il_rdata), .line_ready(il_ready)
    );
    end endgenerate
    rv_cache_2way #(.TAG_STORAGE(DCACHE_TAG_STORAGE)) u_dcache (
        .clk(clk), .rst_n(rst_n), .invalidate(1'b0), .flush_req(fencei_req),
        .flush_done(fencei_done),
        .cpu_req(s_req[S_DDR]), .cpu_we(s_we), .cpu_be(s_be),
        .cpu_addr(s_addr), .cpu_wdata(s_wdata),
        .cpu_rdata(s_rdata[S_DDR*32 +: 32]), .cpu_ready(s_ready[S_DDR]),
        .hit_event(d_hit), .miss_event(d_miss),
        .line_req(dl_req), .line_we(dl_we), .line_addr(dl_addr),
        .line_wdata(dl_wdata), .line_rdata(dl_rdata), .line_ready(dl_ready)
    );
    wire line_req, line_we, line_ready;
    wire [31:0] line_addr;
    wire [255:0] line_wdata, line_rdata;
    cache_line_arbiter u_arb (
        .clk(clk), .rst_n(rst_n),
        .i_req(il_req), .i_addr(il_addr), .i_rdata(il_rdata), .i_ready(il_ready),
        .d_req(dl_req), .d_we(dl_we), .d_addr(dl_addr), .d_wdata(dl_wdata),
        .d_rdata(dl_rdata), .d_ready(dl_ready),
        .mem_req(line_req), .mem_we(line_we), .mem_addr(line_addr), .mem_wdata(line_wdata),
        .mem_rdata(line_rdata), .mem_ready(line_ready)
    );
    ddr3_line_bridge u_ddr_bridge (
        .clk(clk), .rst_n(rst_n), .ddr_init_done(ddr_init_done),
        .line_req(line_req), .line_we(line_we), .line_addr(line_addr),
        .line_wdata(line_wdata), .line_rdata(line_rdata), .line_ready(line_ready),
        .axi_awaddr(axi_awaddr), .axi_awuser_ap(axi_awuser_ap),
        .axi_awuser_id(axi_awuser_id), .axi_awlen(axi_awlen),
        .axi_awready(axi_awready), .axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb), .axi_wready(axi_wready),
        .axi_araddr(axi_araddr), .axi_aruser_ap(axi_aruser_ap),
        .axi_aruser_id(axi_aruser_id), .axi_arlen(axi_arlen),
        .axi_arready(axi_arready), .axi_arvalid(axi_arvalid),
        .axi_rdata(axi_rdata), .axi_rvalid(axi_rvalid), .axi_rlast(axi_rlast)
    );

    wire uart_irq, gpio_irq;
    uart #(.CLK_HZ(100_000_000), .BAUD(115200)) u_uart (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_UART]), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(s_rdata[S_UART*32 +: 32]), .ready(s_ready[S_UART]),
        .irq(uart_irq), .rxd(uart_rxd), .txd(uart_txd)
    );
    gpio #(.N_OUT(8), .N_IN(8)) u_gpio (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_GPIO]), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(s_rdata[S_GPIO*32 +: 32]), .ready(s_ready[S_GPIO]),
        .irq(gpio_irq), .gpio_out(gpio_out), .gpio_in(gpio_in)
    );
    clint u_clint (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_CLINT]), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(s_rdata[S_CLINT*32 +: 32]), .ready(s_ready[S_CLINT]),
        .msip(irq_sw), .mtip(irq_tim)
    );
    perf_counter u_perf (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_PERF]), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(s_rdata[S_PERF*32 +: 32]), .ready(s_ready[S_PERF]),
        .events({ev_tr, ev_ds, ev_is, ev_lu, ev_mp, ev_br, ev_ret, 1'b1})
    );
    ai_conv3x3 #(.ENABLE_BLOCK(ENABLE_AI_BLOCK),.ENABLE_WINDOW(ENABLE_AI_WINDOW),.ENABLE_QUANT(ENABLE_AI_QUANT),.ENABLE_BLOCK8(ENABLE_AI_BLOCK8)) u_ai (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_AI]), .we(s_we), .be(s_be),
        .addr(s_addr), .wdata(s_wdata),
        .rdata(s_rdata[S_AI*32 +: 32]), .ready(s_ready[S_AI])
    );
    cache_stats #(.SPLIT_COUNTERS(CACHE_STATS_SPLIT_COUNTERS)) u_cache_stats (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_CACHE_STATS]), .we(s_we), .be(s_be),
        .addr(s_addr), .wdata(s_wdata),
        .rdata(s_rdata[S_CACHE_STATS*32 +: 32]), .ready(s_ready[S_CACHE_STATS]),
        .i_hit(i_hit), .i_miss(i_miss), .d_hit(d_hit), .d_miss(d_miss)
    );
    assign irq_ext = uart_irq | gpio_irq;
endmodule
