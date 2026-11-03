// Shares one line-transfer port between instruction and data caches.
// Requests remain asserted until their ready response; D-side wins a tie.
module cache_line_arbiter (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         i_req,
    input  wire [31:0]  i_addr,
    output wire [255:0] i_rdata,
    output wire         i_ready,
    input  wire         d_req,
    input  wire         d_we,
    input  wire [31:0]  d_addr,
    input  wire [255:0] d_wdata,
    output wire [255:0] d_rdata,
    output wire         d_ready,
    output wire         mem_req,
    output wire         mem_we,
    output wire [31:0]  mem_addr,
    output wire [255:0] mem_wdata,
    input  wire [255:0] mem_rdata,
    input  wire         mem_ready
);
    reg active, owner_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            owner_d <= 1'b0;
        end else if (!active) begin
            if (d_req || i_req) begin
                owner_d <= d_req;
                active <= 1'b1;
            end
        end else if (mem_ready) begin
            active <= 1'b0;
        end
    end

    assign mem_req = active;
    assign mem_we = active && owner_d && d_we;
    assign mem_addr = owner_d ? d_addr : i_addr;
    assign mem_wdata = d_wdata;
    assign i_rdata = mem_rdata;
    assign d_rdata = mem_rdata;
    assign i_ready = active && !owner_d && mem_ready;
    assign d_ready = active && owner_d && mem_ready;
endmodule
