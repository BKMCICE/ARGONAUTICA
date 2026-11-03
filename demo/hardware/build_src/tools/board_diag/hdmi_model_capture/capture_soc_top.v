// H04Z PRIVATE RAW320 sampler: preserve W diagnostics/ownership; add six read-only identity words.
// Isolated H04D full-SoC candidate derived from production soc_top_ddr.
// RV32 SoC with 64 KiB boot TCM and cached DDR3 window at 0x8000_0000.
// clk is the DDR controller's 100 MHz UI clock; no CPU/DDR clock crossing.
module capture_soc_top #(
    parameter RAM_INIT_FILE = "",
    parameter ENABLE_BTB = 1,
    parameter ENABLE_AI_BLOCK = 1,
    parameter ENABLE_AI_WINDOW = 0,
    parameter ENABLE_AI_QUANT = 1,
    parameter ENABLE_AI_BLOCK8 = 1,
    parameter CACHE_STATS_SPLIT_COUNTERS = 0,
    parameter REGFILE_STORAGE = 1,
    parameter ENABLE_PIPELINE_PROBE = 0,
    parameter CAPTURE_W = 1920, CAPTURE_H = 1080, FIFO_ADDR_BITS = 9,
    parameter ENABLE_RESULT_UI = 0,
    parameter ENABLE_FLASH_BOOT = 0,
    parameter AI_LATCH_SHAPE = 1
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         ddr_init_done,
    input wire pix_clk,pix_reset_n,capture_ready,
    input wire [26:0] capture_sample,
    output wire diag_request,input wire diag_busy,diag_valid,diag_timeout,
    input wire [31:0] diag_sequence,input wire [511:0] diag_data,
    input  wire         uart_rxd,
    output wire         uart_txd,
    output wire [7:0]   gpio_out,
    output wire ui_command_valid,
    output wire [23:0] ui_command,
    input wire ui_busy,ui_protocol_error,
    input wire flash_miso,
    output wire flash_cs_n,flash_sck,flash_mosi,flash_wp_n,flash_hold_n,
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
    wire dmem_owned,dmem_consume;
    wire irq_sw, irq_tim, irq_ext;
    wire ev_ret, ev_br, ev_mp, ev_lu, ev_is, ev_ds, ev_tr;
    wire fetch_flush, fencei_req, fencei_done;
    rv_core #(.ENABLE_M(1), .ENABLE_BTB(ENABLE_BTB), .ENABLE_CACHE_FENCE(1), .REGFILE_STORAGE(REGFILE_STORAGE), .ENABLE_PIPELINE_PROBE(ENABLE_PIPELINE_PROBE), .TRANSACTIONAL_DMEM(1)) u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_req(imem_req), .imem_addr(imem_addr), .imem_rdata(imem_rdata), .imem_ready(imem_ready), .imem_fault(imem_fault),
        .dmem_req(dmem_req), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready), .dmem_fault(dmem_fault),
        .dmem_owned(dmem_owned), .dmem_consume(dmem_consume),
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

    localparam S_RAM = 0, S_DDR = 1, S_UART = 2, S_GPIO = 3, S_CLINT = 4, S_PERF = 5, S_AI = 6, S_CACHE_STATS = 7, S_FRAME = 8;
    localparam NS = 9;
    wire [NS-1:0] sel, s_req, bus_s_req, s_ready;
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
    assign sel[S_FRAME] = dmem_addr[31:12] == 20'h40006;
    // Nine disjoint windows, including frame control.
    wire bus_fault,frame_access_fault;
    wire txn_req,txn_issue,txn_we,txn_ready,txn_fault;
    wire [3:0] txn_be;
    wire [31:0] txn_addr,txn_wdata,txn_rdata;
    wire [NS-1:0] txn_sel;
    // Fault classification depends on registered target/payload and current
    // frame policy, never on the outgoing req. No req/fault/trap feedback.
    assign txn_fault=bus_fault|(txn_sel[S_DDR]&&frame_access_fault);
    rv_data_transaction_boundary #(.SELECT_WIDTH(NS)) data_transaction(
        .clk(clk),.rst_n(rst_n),
        .core_req(dmem_req),.core_we(dmem_we),.core_be(dmem_be),
        .core_addr(dmem_addr),.core_wdata(dmem_wdata),.core_sel(sel),
        .core_owned(dmem_owned),.core_ready(dmem_ready),.core_fault(dmem_fault),
        .core_rdata(dmem_rdata),.core_consume(dmem_consume),
        .target_req(txn_req),.target_issue(txn_issue),.target_we(txn_we),.target_be(txn_be),
        .target_addr(txn_addr),.target_wdata(txn_wdata),.target_sel(txn_sel),
        .target_ready(txn_ready),.target_fault(txn_fault),.target_rdata(txn_rdata));
    soc_bus #(.N_SLAVES(NS), .ONE_HOT_SELECT(1)) u_bus (
        .m_req(txn_req), .m_we(txn_we), .m_be(txn_be), .m_addr(txn_addr), .m_wdata(txn_wdata),
        .m_rdata(txn_rdata), .m_ready(txn_ready), .m_fault(bus_fault), .sel(txn_sel),
        .s_req(bus_s_req), .s_we(s_we), .s_be(s_be), .s_addr(s_addr), .s_wdata(s_wdata),
        .s_rdata(s_rdata), .s_ready(s_ready)
    );
    // Contract: the real address decoder above produces zero or exactly one
    // select, captured together with payload. For PERF/AI the selected address
    // cannot be DDR, and bus_fault is false, so ISSUE & txn_sel is equivalent
    // to bus_s_req without the unrelated frame-permission control cone.
    // This is not a contract for arbitrary injected multi-hot selections.
    // DDR and all other slaves keep the original fault-gated bus request.
    assign s_req[S_PERF] = txn_issue && txn_sel[S_PERF];
    assign s_req[S_AI] = txn_issue && txn_sel[S_AI];
    assign s_req[S_PERF-1:0] = bus_s_req[S_PERF-1:0];
    assign s_req[NS-1:S_AI+1] = bus_s_req[NS-1:S_AI+1];
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
    wire i_hit,i_miss,d_hit,d_miss;
    wire [31:0] frame_rdata;
    (* async_reg="true",syn_preserve=1 *) reg [1:0] ready_sync=0;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) ready_sync<=0; else ready_sync<={ready_sync[0],capture_ready};
    wire model_identity_window=(s_addr[11:0]==12'h090)||(s_addr[11:0]==12'h094)||
        (s_addr[11:0]==12'h098)||(s_addr[11:0]==12'h09c)||
        (s_addr[11:0]==12'h0a0)||(s_addr[11:0]==12'h0a4);
    wire frame_window=(s_addr[11:5]==0)||model_identity_window;
    wire [31:0] diag_rdata,fault_rdata;wire diag_ready,fault_ready;
    wire fault_window=s_addr[11:4]==8'h07||s_addr[11:3]==9'h010;
    hdmi_diagnostic_mmio diag_mmio(
        .clk(clk),.rst_n(rst_n),.req(s_req[S_FRAME]&&!frame_window&&!fault_window),.we(s_we),.be(s_be),
        .addr(s_addr[11:0]),.wdata(s_wdata),.snapshot_busy(diag_busy),.snapshot_valid(diag_valid),
        .snapshot_timeout(diag_timeout),.snapshot_sequence(diag_sequence),.snapshot_data(diag_data),
        .snapshot_request(diag_request),.ready(diag_ready),.rdata(diag_rdata));
    assign s_ready[S_FRAME]=frame_window ? s_req[S_FRAME] : fault_window ? fault_ready : diag_ready;
    assign s_rdata[S_FRAME*32+:32]=frame_window ?
        (s_addr[11:0]==12'h01c ? {31'b0,ready_sync[1]} : frame_rdata) : fault_window ? fault_rdata : diag_rdata;
    hdmi_frame_memory #(.EXPECT_W(CAPTURE_W),.EXPECT_H(CAPTURE_H),.FIFO_ADDR_BITS(FIFO_ADDR_BITS)) frame_memory(
        .clk(clk),.pix_clk(pix_clk),.rst_n(rst_n),.pix_reset_n(pix_reset_n),.ddr_init_done(ddr_init_done),
        .fault_req(s_req[S_FRAME]&&fault_window),.fault_we(s_we),.fault_be(s_be),
        .fault_addr(s_addr[11:0]),.fault_wdata(s_wdata),.fault_ready(fault_ready),.fault_rdata(fault_rdata),
        .cpu_i_req(cache_i_req),.cpu_i_addr(cache_i_addr),.cpu_i_rdata(cache_i_word),.cpu_i_ready(cache_i_word_ready),
        .cpu_d_req(s_req[S_DDR]),.cpu_d_we(s_we),.cpu_d_be(s_be),.cpu_d_addr(s_addr),.cpu_d_wdata(s_wdata),
        .cpu_d_rdata(s_rdata[S_DDR*32+:32]),.cpu_d_ready(s_ready[S_DDR]),.cpu_d_fault(frame_access_fault),
        .fence_req(fencei_req),.fence_done(fencei_done),
        .ctrl_req(s_req[S_FRAME]&&frame_window),.ctrl_we(s_we),.ctrl_be(s_be),.ctrl_addr(s_addr),.ctrl_wdata(s_wdata),
        .ctrl_rdata(frame_rdata),.ctrl_ready(),
        .de(capture_sample[24]),.hs(capture_sample[26]),.vs(capture_sample[25]),.rgb(capture_sample[23:0]),
        .cpu_block(),.dma_lease(),.frame_valid(),.frame_owned(),.job_busy(),
        .i_hit(i_hit),.i_miss(i_miss),.d_hit(d_hit),.d_miss(d_miss),
        .axi_awaddr(axi_awaddr),.axi_araddr(axi_araddr),.axi_awuser_ap(axi_awuser_ap),.axi_aruser_ap(axi_aruser_ap),
        .axi_awuser_id(axi_awuser_id),.axi_aruser_id(axi_aruser_id),.axi_awlen(axi_awlen),.axi_arlen(axi_arlen),
        .axi_awready(axi_awready),.axi_arready(axi_arready),.axi_wready(axi_wready),
        .axi_awvalid(axi_awvalid),.axi_arvalid(axi_arvalid),.axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),
        .axi_rdata(axi_rdata),.axi_rvalid(axi_rvalid),.axi_rlast(axi_rlast));

    wire uart_irq, gpio_irq;
    uart #(.CLK_HZ(100_000_000), .BAUD(115200)) u_uart (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_UART]), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(s_rdata[S_UART*32 +: 32]), .ready(s_ready[S_UART]),
        .irq(uart_irq), .rxd(uart_rxd), .txd(uart_txd)
    );
    // H19 intercepts only the previously unused exact GPIO+0x10 word.
    // No new slave/decoder window or changes to original GPIO/IRQ/UI commands.
    wire flash_window=ENABLE_FLASH_BOOT && s_addr[11:0]==12'h010;
    wire [31:0] flash_rdata;
    generate if(ENABLE_FLASH_BOOT)begin: flash_user
        h19_spi_gpio spi_gpio(.clk(clk),.rst_n(rst_n),.request(s_req[S_GPIO]&&flash_window),
            .we(s_we),.be(s_be),.wdata(s_wdata),.flash_miso(flash_miso),.rdata(flash_rdata),
            .flash_cs_n(flash_cs_n),.flash_sck(flash_sck),.flash_mosi(flash_mosi),
            .flash_wp_n(flash_wp_n),.flash_hold_n(flash_hold_n));
    end else begin: no_flash_user
        assign flash_rdata=0;
        assign {flash_cs_n,flash_sck,flash_mosi,flash_wp_n,flash_hold_n}=5'b10011;
    end endgenerate
    // H18 private sideband observes only the original accepted GPIO store.
    // Original GPIO low byte, input synchronizers, IRQ and slave count remain.
    wire [31:0] gpio_rdata;
    assign ui_command_valid=ENABLE_RESULT_UI && !flash_window && s_req[S_GPIO] && s_we && (&s_be) &&
        s_addr[3:2]==0 && s_wdata[31:29]==3'b101;
    assign ui_command=s_wdata[31:8];
    assign s_rdata[S_GPIO*32+:32]=flash_window ? flash_rdata : (ENABLE_RESULT_UI && s_addr[3:2]==0) ?
        {16'h4831,ui_busy,ui_protocol_error,6'b0,gpio_rdata[7:0]} : gpio_rdata;
    gpio #(.N_OUT(8), .N_IN(8)) u_gpio (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_GPIO]&&!flash_window), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(gpio_rdata), .ready(s_ready[S_GPIO]),
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
    ai_conv3x3 #(.ENABLE_BLOCK(ENABLE_AI_BLOCK),.ENABLE_WINDOW(ENABLE_AI_WINDOW),.ENABLE_QUANT(ENABLE_AI_QUANT),.ENABLE_BLOCK8(ENABLE_AI_BLOCK8),.LATCH_SHAPE_VALID(AI_LATCH_SHAPE)) u_ai (
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
