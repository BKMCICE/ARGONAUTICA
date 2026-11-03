// A39 optional tag store. Both backends have the same synchronous-read port.
// No reset or initialization: the cache's valid bits hide stale tag contents.
// The controller never enables read and write on the same cycle; no_rw_check
// is deliberately not used. STORAGE=1 registers, STORAGE=2 vendor block RAM.
module rv_cache_tag_store #(
    parameter SET_BITS = 6,
    parameter TAG_BITS = 27 - SET_BITS,
    parameter STORAGE = 2
)(
    input wire clk,
    input wire write_enable,
    input wire [SET_BITS-1:0] write_set,
    input wire [TAG_BITS-1:0] write_tag,
    input wire read_enable,
    input wire [SET_BITS-1:0] read_set,
    output reg [TAG_BITS-1:0] read_tag
);
    generate if (STORAGE == 1) begin : registers
        reg [TAG_BITS-1:0] mem [0:(1<<SET_BITS)-1]
            /* synthesis syn_ramstyle="registers" */;
        always @(posedge clk)
            if (write_enable) mem[write_set] <= write_tag;
        always @(posedge clk)
            if (read_enable) read_tag <= mem[read_set];
    end else begin : block_ram
        reg [TAG_BITS-1:0] mem [0:(1<<SET_BITS)-1]
            /* synthesis syn_ramstyle="block_ram" */;
        always @(posedge clk)
            if (write_enable) mem[write_set] <= write_tag;
        always @(posedge clk)
            if (read_enable) read_tag <= mem[read_set];
    end endgenerate
`ifndef SYNTHESIS
    initial begin
        if (STORAGE != 1 && STORAGE != 2)
            $fatal(1, "rv_cache_tag_store STORAGE must be 1 or 2");
    end
`endif
endmodule
