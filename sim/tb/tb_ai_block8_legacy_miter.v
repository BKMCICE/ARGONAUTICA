`timescale 1ns/1ps
module tb_ai_block8_legacy_miter;
    reg clk=0,rst_n=0,req=0,we=0;reg [3:0] be=0;reg [31:0] addr=0,wdata=0;
    wire [31:0] got,want;wire gr,wr;
    ai_conv3x3 #(.ENABLE_BLOCK(1),.ENABLE_BLOCK8(1)) current(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),.addr(addr),.wdata(wdata),.rdata(got),.ready(gr));
    ai_conv3x3_reference original(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),.addr(addr),.wdata(wdata),.rdata(want),.ready(wr));
    always #5 clk=~clk;
    integer i;reg [31:0] seed=32'h63301;
    function [31:0] advance(input [31:0] a);begin advance={a[30:0],a[31]^a[21]^a[1]^a[0]};end endfunction
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        for(i=0;i<20000;i=i+1)begin
            @(negedge clk);seed=advance(seed);req=seed[0];we=seed[1];be=seed[5:2];
            // Only original documented legacy registers. New capability0x28 is intentional.
            addr=(seed%10)*4;wdata=advance(seed);
            if(i%997==0)rst_n=0;else rst_n=1;
            #1;if(got!==want || gr!==wr)$fatal(1,"Block8 legacy mismatch cycle=%0d got=%h want=%h",i,got,want);
        end
        $display("A33_BLOCK8_LEGACY_MITER_PASS cycles=20000 documented_legacy_offsets=10");$finish;
    end
endmodule
