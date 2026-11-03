// Test-only replacement of the public wrapper. The runner renames the original
// wrapper to a53_original_ai_conv3x3, preserving its exact source bytes otherwise.
`ifndef A53_ON
`define A53_ON 0
`endif
module ai_conv3x3 #(parameter ENABLE_BLOCK=0,ENABLE_WINDOW=0,ENABLE_QUANT=0,ENABLE_BLOCK8=0,ENABLE_A53=`A53_ON)(
    input wire clk,rst_n,req,we,input wire [3:0] be,
    input wire [31:0] addr,wdata,output wire [31:0] rdata,output wire ready
);
    wire [31:0] original_rdata;
    wire original_ready;
    generate if(ENABLE_A53)begin:new_engine
        wire selected=addr[11:8]==4'h3;
        wire [31:0] batch_rdata;
        wire batch_ready,batch_busy;
        ai_dw3_batch batch(.clk(clk),.rst_n(rst_n),.req(req&&selected),.we(we),
            .conflict(req&&!selected&&batch_busy),.be(be),.addr(addr),.wdata(wdata),
            .rdata(batch_rdata),.ready(batch_ready),.busy(batch_busy));
        a53_original_ai_conv3x3 #(.ENABLE_BLOCK(ENABLE_BLOCK),.ENABLE_WINDOW(ENABLE_WINDOW),
            .ENABLE_QUANT(ENABLE_QUANT),.ENABLE_BLOCK8(ENABLE_BLOCK8)) original(
            .clk(clk),.rst_n(rst_n),.req(req&&!selected&&!batch_busy),.we(we),.be(be),
            .addr(addr),.wdata(wdata),.rdata(original_rdata),.ready(original_ready));
        assign rdata=selected?batch_rdata:(batch_busy?0:original_rdata);
        assign ready=selected?batch_ready:original_ready;
    end else begin:disabled
        a53_original_ai_conv3x3 #(.ENABLE_BLOCK(ENABLE_BLOCK),.ENABLE_WINDOW(ENABLE_WINDOW),
            .ENABLE_QUANT(ENABLE_QUANT),.ENABLE_BLOCK8(ENABLE_BLOCK8)) original(
            .clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),.addr(addr),.wdata(wdata),
            .rdata(rdata),.ready(ready));
    end endgenerate
endmodule
