`timescale 1ns/1ps
module tb_a01_legacy_miter;
reg clk=0,rst_n=0,req=0,we=0;reg [3:0] be=0;reg [31:0] addr=0,wdata=0;
wire [31:0] got,want;wire gr,wr;
ai_conv3x3 current(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),.addr(addr),.wdata(wdata),.rdata(got),.ready(gr));
ai_conv3x3_reference original(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),.addr(addr),.wdata(wdata),.rdata(want),.ready(wr));
always #5 clk=~clk;
integer i;reg [31:0] seed=32'h62a01;
function [31:0] advance(input [31:0] a);begin advance={a[30:0],a[31]^a[21]^a[1]^a[0]};end endfunction
initial begin
repeat(3) @(negedge clk);rst_n=1;
for(i=0;i<20000;i=i+1) begin
@(negedge clk);seed=advance(seed);req=seed[0];we=seed[1];be=seed[5:2];addr=seed&32'hfff;wdata=advance(seed);
if(i%997==0) rst_n=0;else rst_n=1;
#1;if(got!==want || gr!==wr) $fatal(1,"Default legacy mismatch cycle=%0d",i);
end
$display("A01_DEFAULT_LEGACY_MITER_PASS cycles=20000");$finish;
end
endmodule
