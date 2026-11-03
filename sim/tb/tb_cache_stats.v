`timescale 1ns/1ps
module tb_cache_stats #(parameter SPLIT_COUNTERS = 0);
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, req = 0, we = 0;
    reg [31:0] addr = 0, wdata = 0;
    reg [3:0] events = 0;
    wire [31:0] rdata;
    wire ready;
    cache_stats #(.SPLIT_COUNTERS(SPLIT_COUNTERS)) dut(.clk(clk), .rst_n(rst_n), .req(req), .we(we),
        .be(4'hf), .addr(addr), .wdata(wdata), .rdata(rdata), .ready(ready),
        .i_hit(events[3]), .i_miss(events[2]), .d_hit(events[1]), .d_miss(events[0]));

    task tick;
        input [3:0] pulse;
        input write_control;
        input [31:0] control;
        begin
            @(negedge clk);
            events = pulse; req = write_control; we = write_control;
            addr = 0; wdata = control;
            @(posedge clk); #1;
            if (!ready) $fatal(1, "statistics MMIO stalled");
        end
    endtask
    task counts;
        input [31:0] ih, im, dh, dm;
        begin
            addr = 4; #0.1; if (rdata !== ih) $fatal(1, "I hit %0d != %0d", rdata, ih);
            addr = 8; #0.1; if (rdata !== im) $fatal(1, "I miss %0d != %0d", rdata, im);
            addr = 12; #0.1; if (rdata !== dh) $fatal(1, "D hit %0d != %0d", rdata, dh);
            addr = 16; #0.1; if (rdata !== dm) $fatal(1, "D miss %0d != %0d", rdata, dm);
        end
    endtask
    integer n;
    initial begin
        #2; rst_n = 1; #1; rst_n = 0; #1; rst_n = 1;
        tick(4'b1000, 0, 0); counts(0,0,0,0);
        tick(4'b0100, 0, 0); counts(1,0,0,0);
        tick(4'b0010, 0, 0); counts(1,1,0,0);
        tick(4'b0001, 0, 0); counts(1,1,1,0);
        tick(0, 0, 0); counts(1,1,1,1);
        for (n=0; n<32; n=n+1) tick(4'hf, 0, 0);
        tick(0, 0, 0); counts(33,33,33,33);
        // Disabling retires queued events and accepts events under the
        // previous enable value. No later disabled event may slip through.
        tick(4'b1000, 0, 0);
        tick(4'b0100, 1, 0); counts(34,33,33,33);
        tick(4'hf, 0, 0); counts(34,34,33,33);
        tick(4'hf, 1, 1); counts(34,34,33,33);
        tick(4'b0010, 0, 0); counts(34,34,33,33);
        tick(0, 0, 0); counts(34,34,34,33);
        // Clear must discard both a queued and a concurrent event.
        tick(4'hf, 0, 0);
        tick(4'hf, 1, 3); counts(0,0,0,0);
        tick(0, 0, 0); counts(0,0,0,0);
        tick(4'hf, 1, 2); // clear and disable
        tick(4'hf, 0, 0); tick(0, 0, 0); counts(0,0,0,0);
        tick(0, 1, 1); tick(4'hf, 0, 0);
        // Reset also drains the pending stage.
        @(negedge clk); rst_n=0; events=0; req=0; we=0;
        #1; counts(0,0,0,0);
        @(negedge clk); rst_n=1;
        tick(0, 0, 0); counts(0,0,0,0);
        tick(4'hf, 0, 0); tick(0, 0, 0); counts(1,1,1,1);
        $display("CACHE_STATS_PIPELINE_PASS continuous=32 enable_clear_reset=PASS");
        $finish;
    end
endmodule
