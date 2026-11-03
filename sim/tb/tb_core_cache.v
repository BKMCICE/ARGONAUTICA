// CPU + two independent two-way caches + shared burst memory model.
// A tohost store ends the ISA test before the dirty line is evicted.
`timescale 1ns/1ps
module tb_core_cache;
    parameter ENABLE_M = 1;
    parameter ENABLE_BTB = 0;
    parameter ICACHE_DRM = 0;
    parameter ICACHE_EARLY_READ = 0;
    parameter DCACHE_TAG_STORAGE = 0;
    parameter REGFILE_STORAGE = 0;
    parameter ENABLE_PIPELINE_PROBE = 0;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire imem_req, imem_ready, dmem_req, dmem_we, dmem_ready;
    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0] dmem_be;
    wire ev_ret, ev_br, ev_mp, ev_lu, ev_is, ev_ds, ev_tr;
    wire fetch_flush, fencei_req, fencei_done;
    rv_core #(.ENABLE_M(ENABLE_M), .ENABLE_BTB(ENABLE_BTB), .ENABLE_CACHE_FENCE(1), .REGFILE_STORAGE(REGFILE_STORAGE), .ENABLE_PIPELINE_PROBE(ENABLE_PIPELINE_PROBE)) dut (
        .clk(clk), .rst_n(rst_n),
        .imem_req(imem_req), .imem_addr(imem_addr), .imem_rdata(imem_rdata), .imem_ready(imem_ready), .imem_fault(1'b0),
        .dmem_req(dmem_req), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready), .dmem_fault(1'b0),
        .irq_software(1'b0), .irq_timer(1'b0), .irq_external(1'b0),
        .ev_instr_retired(ev_ret), .ev_branch(ev_br), .ev_branch_mispred(ev_mp),
        .ev_load_use_stall(ev_lu), .ev_imem_stall(ev_is), .ev_dmem_stall(ev_ds), .ev_trap(ev_tr),
        .fetch_flush(fetch_flush), .fencei_req(fencei_req), .fencei_done(fencei_done)
    );

    // Check the actual connected observer on every CPU edge, including stalls
    // and traps. All fields must belong to the same pre-edge CPU cycle.
    generate if (ENABLE_PIPELINE_PROBE) begin : probe_checker
        reg [25:0] expected;
        always @(posedge clk) begin
            expected = !rst_n ? 26'b0 :
                {dut.trap_enter, dut.mem_stall, dut.muldiv_stall,
                 dut.ld_use_stall, dut.if_stall, dut.pipe_freeze,
                 dut.mem_commit, dut.exmem_valid, dut.idex_valid,
                 dut.ifid_valid, dut.if_valid,
                 (dut.exmem_pc[31:16] == 16'b0), dut.exmem_pc[15:2]};
            #1;
            if (dut.pipeline_probe_q !== expected) $fatal(1,"PROBE_ALIGNMENT_FAIL");
        end
    end endgenerate

    wire il_req, il_we, il_ready, dl_req, dl_we, dl_ready;
    wire [31:0] il_addr, dl_addr;
    wire [255:0] il_wdata, il_rdata, dl_wdata, dl_rdata;
    wire i_hit, i_miss, d_hit, d_miss;
    wire cache_i_req, cache_i_ready;
    wire [31:0] cache_i_addr, cache_i_rdata;
    imem_cache_adapter u_if_adapter (
        .clk(clk), .rst_n(rst_n), .flush(fetch_flush),
        .core_req(imem_req), .core_addr(imem_addr),
        .core_rdata(imem_rdata), .core_ready(imem_ready),
        .cache_req(cache_i_req), .cache_addr(cache_i_addr),
        .cache_rdata(cache_i_rdata), .cache_ready(cache_i_ready)
    );
    wire [3:0] icache_state;
    generate if (ICACHE_DRM) begin : sync_icache
        rv_icache_drm #(.EARLY_READ(ICACHE_EARLY_READ)) u_icache (
            .clk(clk), .rst_n(rst_n), .invalidate(fencei_done),
            .flush_req(1'b0), .flush_done(),
            .cpu_req(cache_i_req), .cpu_addr(cache_i_addr),
            .cpu_rdata(cache_i_rdata), .cpu_ready(cache_i_ready),
            .hit_event(i_hit), .miss_event(i_miss),
            .line_req(il_req), .line_we(il_we), .line_addr(il_addr),
            .line_wdata(il_wdata), .line_rdata(il_rdata), .line_ready(il_ready));
        assign icache_state=u_icache.state;
    end else begin : original_icache
    rv_cache_2way u_icache (
        .clk(clk), .rst_n(rst_n), .invalidate(fencei_done),
        .flush_req(1'b0), .flush_done(),
        .cpu_req(cache_i_req), .cpu_we(1'b0), .cpu_be(4'b0),
        .cpu_addr(cache_i_addr), .cpu_wdata(32'b0),
        .cpu_rdata(cache_i_rdata), .cpu_ready(cache_i_ready),
        .hit_event(i_hit), .miss_event(i_miss),
        .line_req(il_req), .line_we(il_we), .line_addr(il_addr),
        .line_wdata(il_wdata), .line_rdata(il_rdata), .line_ready(il_ready)
    );
        assign icache_state=u_icache.state;
    end endgenerate
    wire data_is_ram = dmem_addr < 32'h0001_0000;
    wire [31:0] cache_ddata;
    wire cache_dready;
    rv_cache_2way #(.TAG_STORAGE(DCACHE_TAG_STORAGE)) u_dcache (
        .clk(clk), .rst_n(rst_n), .invalidate(1'b0),
        .flush_req(fencei_req), .flush_done(fencei_done),
        .cpu_req(dmem_req && data_is_ram), .cpu_we(dmem_we), .cpu_be(dmem_be),
        .cpu_addr(dmem_addr), .cpu_wdata(dmem_wdata),
        .cpu_rdata(cache_ddata), .cpu_ready(cache_dready),
        .hit_event(d_hit), .miss_event(d_miss),
        .line_req(dl_req), .line_we(dl_we), .line_addr(dl_addr),
        .line_wdata(dl_wdata), .line_rdata(dl_rdata), .line_ready(dl_ready)
    );
    assign dmem_rdata = data_is_ram ? cache_ddata : 32'b0;
    assign dmem_ready = data_is_ram ? cache_dready : 1'b1;

    wire mem_req, mem_we, mem_ready;
    wire [31:0] mem_addr;
    wire [255:0] mem_wdata, mem_rdata;
    cache_line_arbiter u_arb (
        .clk(clk), .rst_n(rst_n),
        .i_req(il_req), .i_addr(il_addr), .i_rdata(il_rdata), .i_ready(il_ready),
        .d_req(dl_req), .d_we(dl_we), .d_addr(dl_addr), .d_wdata(dl_wdata),
        .d_rdata(dl_rdata), .d_ready(dl_ready),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );
    burst_ram_model u_mem (
        .clk(clk), .rst_n(rst_n), .req(mem_req), .we(mem_we), .addr(mem_addr),
        .wdata(mem_wdata), .rdata(mem_rdata), .ready(mem_ready)
    );

    integer cycles = 0, retired = 0, ihits = 0, imisses = 0, dhits = 0, dmisses = 0;
    integer timeout_cycles = 2000000, trace_cycles = 0;
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (ev_ret) retired <= retired + 1;
        if (i_hit) ihits <= ihits + 1;
        if (i_miss) imisses <= imisses + 1;
        if (d_hit) dhits <= dhits + 1;
        if (d_miss) dmisses <= dmisses + 1;
        if (trace_cycles > 0 && cycles < trace_cycles && ev_ret)
            $display("TRACE cyc=%0d pc=%h instr=%h next=%h if={valid:%b ready:%b req:%b adapter:%b/%b cache:%0d}",
                     cycles, dut.exmem_pc, dut.exmem_instr, dut.pc, dut.if_valid,
                     imem_ready, imem_req, u_if_adapter.active, u_if_adapter.wanted_valid,
                     icache_state);
        if (dmem_req && dmem_ready && dmem_we && dmem_addr == 32'h4000_0000)
            $write("%c", dmem_wdata[7:0]);
        if (dmem_req && dmem_ready && dmem_we && dmem_addr == 32'h0000_F000) begin
            if (dmem_wdata == 1)
                $display("[PASS] cache cycles=%0d instrs=%0d ihit=%0d imiss=%0d dhit=%0d dmiss=%0d",
                         cycles, retired, ihits, imisses, dhits, dmisses);
            else
                $display("[FAIL] tohost=%h", dmem_wdata);
            $finish;
        end
        if (cycles == timeout_cycles) begin
            $display("[TIMEOUT] pc=%h if_valid=%b imem_ready=%b req=%b adapter=%b/%b wanted=%h active=%h icache=%0d dcache=%0d",
                     dut.pc, dut.if_valid, imem_ready, imem_req,
                     u_if_adapter.active, u_if_adapter.wanted_valid,
                     u_if_adapter.wanted_addr, u_if_adapter.active_addr,
                     icache_state, u_dcache.state);
            $finish;
        end
    end
    initial begin
        if (!$value$plusargs("timeout=%d", timeout_cycles)) timeout_cycles = 2000000;
        if (!$value$plusargs("trace=%d", trace_cycles)) trace_cycles = 0;
        #33 rst_n = 1;
    end
endmodule
