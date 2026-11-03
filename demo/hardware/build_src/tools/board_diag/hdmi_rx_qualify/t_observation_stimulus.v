`timescale 1ns/1ps
// Test-only RX silicon-boundary stimulus. Real S wire/controller is separately frozen.
module t_observation_stimulus #(parameter PERIOD=128)(input wire clk,rst_n,
 input wire enable,good,error,output reg valid=0,busy=0,last_error=0,
 output reg [31:0] raw=0,seq=0,age=32'hffffffff);
 integer phase=0;
 always @(negedge clk) begin
  if(!rst_n)begin phase=0;valid=0;busy=0;last_error=0;raw=0;seq=0;age=32'hffffffff;end
  else begin
   if(age!=32'hffffffff)age=age+1;
   if(enable)begin
    if(phase==0)busy=1;
    if(phase==4)begin
     busy=0;last_error=error;
     if(!error)begin valid=1;raw=good?32'h00007f07:32'h00004f07;seq=seq+1;age=0;end
    end
    if(phase==PERIOD-1)phase=0;else phase=phase+1;
   end else begin busy=0;phase=0;end
  end
 end
endmodule
