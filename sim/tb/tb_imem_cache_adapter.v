// Real blocking I-cache plus a variable-latency, deterministic line source.
// Check redirects during a miss/response, newest-PC replacement, reset, and
// back-to-back warm fetches without depending on the adapter's internals.
`timescale 1ns/1ps
module tb_imem_cache_adapter #(parameter ICACHE_DRM=0, parameter ICACHE_EARLY_READ=0);
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg flush = 0, core_req = 0;
    reg [31:0] core_addr = 0;
    wire core_ready, cache_req, cache_ready;
    wire [31:0] core_rdata, cache_addr, cache_rdata;
    wire line_req, line_ready, line_we;
    wire [31:0] line_addr;
    wire [255:0] line_wdata;
    reg [255:0] line_rdata;
    reg mem_active = 0;
    reg [31:0] held_addr;
    integer remaining = 0, cycles = 0, responses = 0;
    integer max_warm_cycles = 5;
    reg expected_valid = 0;
    reg [31:0] expected_addr;
    imem_cache_adapter dut (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .core_req(core_req), .core_addr(core_addr),
        .core_ready(core_ready), .core_rdata(core_rdata),
        .cache_req(cache_req), .cache_addr(cache_addr),
        .cache_ready(cache_ready), .cache_rdata(cache_rdata)
    );
    generate if (ICACHE_DRM) begin : sync_cache
        rv_icache_drm #(.EARLY_READ(ICACHE_EARLY_READ)) cache (
            .clk(clk), .rst_n(rst_n), .invalidate(1'b0), .flush_req(1'b0), .flush_done(),
            .cpu_req(cache_req), .cpu_addr(cache_addr),
            .cpu_ready(cache_ready), .cpu_rdata(cache_rdata), .hit_event(), .miss_event(),
            .line_req(line_req), .line_we(line_we), .line_addr(line_addr), .line_wdata(line_wdata),
            .line_ready(line_ready), .line_rdata(line_rdata));
    end else begin : original_cache
    rv_cache_2way cache (
        .clk(clk), .rst_n(rst_n), .invalidate(1'b0), .flush_req(1'b0), .flush_done(),
        .cpu_req(cache_req), .cpu_we(1'b0), .cpu_be(4'b0), .cpu_addr(cache_addr), .cpu_wdata(32'b0),
        .cpu_ready(cache_ready), .cpu_rdata(cache_rdata), .hit_event(), .miss_event(),
        .line_req(line_req), .line_we(line_we), .line_addr(line_addr), .line_wdata(line_wdata),
        .line_ready(line_ready), .line_rdata(line_rdata)
    );
    end endgenerate
    function [31:0] word_at;
        input [31:0] addr;
        begin word_at = addr ^ 32'ha5c31729; end
    endfunction
    assign line_ready = mem_active && remaining == 0;
    integer lane;
    always @* begin
        for (lane = 0; lane < 8; lane = lane + 1)
            line_rdata[lane*32 +: 32] = word_at(held_addr + lane*4);
    end
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (cycles > 5000) $fatal(1, "adapter test timeout");
        if (!rst_n) begin mem_active <= 0; remaining <= 0; end
        else if (!mem_active && line_req) begin
            if (line_we) $fatal(1, "instruction cache wrote backing memory");
            mem_active <= 1;
            held_addr <= line_addr;
            remaining <= 3 + line_addr[7:5];
        end else if (mem_active && remaining != 0) remaining <= remaining - 1;
        else if (line_ready) mem_active <= 0;
        // The CPU ignores a simultaneous flush/response. A new request can
        // arrive on a response edge; it replaces the just-consumed request.
        if (!rst_n || flush) expected_valid = 0;
        else begin
            if (core_ready) begin
                if (!expected_valid || core_rdata !== word_at(expected_addr))
                    $fatal(1, "stale/duplicate response: expected valid=%b PC=%h, got %h", expected_valid, expected_addr, core_rdata);
                expected_valid = 0;
                responses = responses + 1;
            end
            if (core_req) begin expected_addr = core_addr; expected_valid = 1; end
        end
    end
    task issue;
        input [31:0] addr;
        begin
            @(negedge clk); core_addr = addr; core_req = 1;
            @(negedge clk); core_req = 0;
        end
    endtask
    task await_response;
        begin
            wait(core_ready);
            @(negedge clk);
        end
    endtask
    task redirect;
        begin
            @(negedge clk); flush = 1;
            @(negedge clk); flush = 0;
        end
    endtask
    integer i, started, elapsed;
    initial begin
        if (!$value$plusargs("max_warm_cycles=%d", max_warm_cycles)) max_warm_cycles = 5;
        #22 rst_n = 1;
        issue(32'h80000000); await_response();
        // A redirect before a cold fill returns must suppress the old word.
        issue(32'h80000100);
        redirect();
        issue(32'h80000204); await_response();
        // Keep only the newest requested PC while the old fill drains.
        issue(32'h80000300);
        issue(32'h80000404);
        issue(32'h80000508); await_response();
        // Flush on exactly the response edge, with a simultaneous request.
        issue(32'h8000050c);
        wait(core_ready);
        @(negedge clk);
        flush = 1; core_req = 1; core_addr = 32'h80000600;
        @(negedge clk); flush = 0; core_req = 0;
        issue(32'h80000700); await_response();
        // Reset with an outstanding miss; no stale response may survive.
        issue(32'h80000800);
        @(negedge clk); rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        issue(32'h80000900); await_response();
        // Consecutive requests are issued on the previous response edge,
        // just as the CPU front-end does. The whole line is now warm.
        @(negedge clk); core_req = 1; core_addr = 32'h80000904;
        for (i = 0; i < 32; i = i + 1) begin
            started = cycles;
            @(negedge clk); core_req = 0;
            wait(core_ready);
            elapsed = cycles - started;
            if (elapsed > max_warm_cycles)
                $fatal(1, "warm fetch took %0d cycles (limit %0d)", elapsed, max_warm_cycles);
            $display("WARM_FETCH sample=%0d cycles=%0d", i, elapsed);
            core_req = 1; core_addr = 32'h80000900 + ((i + 2) % 8)*4;
            @(negedge clk);
        end
        core_req = 0;
        await_response();
        repeat (20) @(negedge clk);
        if (expected_valid) $fatal(1, "lost final response");
        $display("IMEM_ADAPTER_PASS responses=%0d cycles=%0d", responses, cycles);
        $finish;
    end
endmodule
