`timescale 1ns/1ps
module tb_ram_bounds;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg i_req = 0, d_req = 0, d_we = 0;
    reg [31:0] i_addr = 0, d_addr = 0, d_wdata = 0;
    wire [31:0] i_rdata, d_rdata;
    wire i_ready, i_fault, d_ready;

    soc_ram #(.ADDR_WIDTH(14)) dut (
        .clk(clk), .rst_n(rst_n),
        .i_req(i_req), .i_addr(i_addr), .i_rdata(i_rdata), .i_ready(i_ready), .i_fault(i_fault),
        .d_req(d_req), .d_we(d_we), .d_be(4'hf), .d_addr(d_addr),
        .d_wdata(d_wdata), .d_rdata(d_rdata), .d_ready(d_ready)
    );

    initial begin
        #12 rst_n = 1;
        dut.mem[0] = 32'h12345678;
        @(negedge clk);
        i_req = 1; i_addr = 32'h00010000;
        d_req = 1; d_we = 1; d_addr = 32'h00010000;
        d_wdata = 32'hcafebabe;
        @(negedge clk);
        if (i_rdata !== 32'h0 || i_fault !== 1'b1 || dut.mem[0] !== 32'h12345678)
            $fatal(1, "out-of-range access aliased RAM word 0");
        d_req = 0; d_we = 0;
        repeat (3) @(negedge clk);
        d_req = 1; d_addr = 32'h00010000;
        @(negedge clk);
        if (d_rdata !== 32'hdeadbeef)
            $fatal(1, "out-of-range read did not return sentinel");
        $display("[PASS] 64 KB RAM bounds");
        $finish;
    end
endmodule
