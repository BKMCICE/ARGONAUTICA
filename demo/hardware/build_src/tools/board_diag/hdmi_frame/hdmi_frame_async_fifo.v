// H04B dual-clock record FIFO with synchronous RAM read and one output stage.
// rst_n is a SHARED asynchronous epoch reset. Assertion clears both domains,
// even when either clock stops; each domain releases through two local flops.
// Only those flops see raw rst_n. Functional flops use the LOCAL synchronized
// reset at their asynchronous reset pins, not just as a clock enable.
// Independent raw pointer resets are forbidden. Physical integration still
// needs Gray-bus delay/skew constraints and actual dual-clock RAM inference.
module hdmi_frame_async_fifo #(
    parameter WIDTH=258, ADDR_BITS=6
)(
    input wire rst_n,wclk,rclk,
    input wire wvalid,output wire wready,input wire [WIDTH-1:0] wdata,
    output reg rvalid,input wire rready,output reg [WIDTH-1:0] rdata,
    output wire w_up,r_up
);
    localparam PTR=ADDR_BITS+1;
    (* async_reg="true",syn_preserve=1 *) reg [1:0] wr_reset=0,rd_reset=0;
    always @(posedge wclk or negedge rst_n)
        if(!rst_n) wr_reset<=0;else wr_reset<={wr_reset[0],1'b1};
    always @(posedge rclk or negedge rst_n)
        if(!rst_n) rd_reset<=0;else rd_reset<={rd_reset[0],1'b1};
    assign w_up=wr_reset[1];assign r_up=rd_reset[1];
    reg [WIDTH-1:0] memory[0:(1<<ADDR_BITS)-1]
        /* synthesis syn_ramstyle="block_ram" */;
    reg [PTR-1:0] wb=0,wg=0,rb=0,rg=0;
    (* async_reg="true",syn_preserve=1 *) reg [PTR-1:0] rg_w1=0,rg_w2=0,wg_r1=0,wg_r2=0;
    reg full=0;
    wire push=wvalid&&wready;
    wire [PTR-1:0] wb_next=wb+push;
    wire [PTR-1:0] wg_next=(wb_next>>1)^wb_next;
    wire full_next=wg_next=={~rg_w2[PTR-1:PTR-2],rg_w2[PTR-3:0]};
    wire empty=rg==wg_r2;
    wire pop_ram=rd_reset[1]&&(!rvalid||rready)&&!empty;
    wire [PTR-1:0] rb_next=rb+1'b1;
    assign wready=wr_reset[1]&&!full;
    always @(posedge wclk or negedge w_up) begin
        if(!w_up) begin wb<=0;wg<=0;full<=0;rg_w1<=0;rg_w2<=0;end
        else begin
            rg_w1<=rg;rg_w2<=rg_w1;
            wb<=wb_next;wg<=wg_next;full<=full_next;
        end
    end
    // Keep RAM ports free of reset logic. Old data is hidden by reset pointers.
    always @(posedge wclk) if(push) memory[wb[ADDR_BITS-1:0]]<=wdata;
    always @(posedge rclk) if(pop_ram) rdata<=memory[rb[ADDR_BITS-1:0]];
    always @(posedge rclk or negedge r_up) begin
        if(!r_up) begin rb<=0;rg<=0;rvalid<=0;wg_r1<=0;wg_r2<=0;end
        else begin
            wg_r1<=wg;wg_r2<=wg_r1;
            if(!rvalid||rready) begin
                rvalid<=!empty;
                if(!empty) begin rb<=rb_next;rg<=(rb_next>>1)^rb_next;end
            end
        end
    end
`ifndef SYNTHESIS
    initial if(ADDR_BITS<2) $fatal(1,"FIFO ADDR_BITS must be >=2");
`endif
endmodule
