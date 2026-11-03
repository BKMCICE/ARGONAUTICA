// Diagnostic RGB888 loop: falling-edge capture, rising-edge output stage.
// RX PCLK is forwarded unchanged. TX MS7210 uses1281=04 (clock inversion).
// This module does not establish missing external PHY AC/PCB bounds.
module hdmi_rgb_loop(input wire pix_clk,rst_n,enable,
 input wire in_hs,in_vs,in_de,input wire [23:0] in_rgb,
 output wire out_clk,output wire [26:0] capture_sample,output reg out_hs,out_vs,out_de,
 output reg [23:0] out_rgb);
 // Forward from the same global clock tree as the data registers. A raw
 // input-to-output wire has a different insertion delay and failed the
 // unchanged half-cycle output reference-plane budget in R0/R1.
`ifdef SYNTHESIS
 GTP_ODDR_E2 #(.GRS_EN("FALSE")) clock_forward(
  .CLK(pix_clk),.D0(1'b1),.D1(1'b0),.T(1'b0),.RS(1'b0),.Q(out_clk),.TQ());
`else
 assign out_clk=pix_clk;
`endif
 (* syn_preserve=1,async_reg="true" *) reg [1:0] ready=0;
 reg [26:0] half_stage=0;
 assign capture_sample=half_stage;
 // Split the IO path. External zero-delay PORT reference remains unchanged:
 // falling-edge capture avoids the rising-edge IO hold-fix detour; the next
 // rising-edge stage gives a complete half-cycle for crossing the fabric.
 always @(negedge pix_clk or negedge rst_n)begin
  if(!rst_n)half_stage<=0;else half_stage<={in_hs,in_vs,in_de,in_rgb};
 end
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)ready<=0;else ready<={ready[0],enable};
 end
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin out_hs<=0;out_vs<=0;out_de<=0;out_rgb<=0;end
  else if(ready[1])begin {out_hs,out_vs,out_de,out_rgb}<=half_stage;end
  else begin out_hs<=0;out_vs<=0;out_de<=0;out_rgb<=0;end
 end
endmodule
