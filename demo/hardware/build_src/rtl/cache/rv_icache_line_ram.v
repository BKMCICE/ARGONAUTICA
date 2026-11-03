// One refill write port and one synchronous line read port, same clock.
// No RAM/output reset: cache valid bits prevent observing unwritten entries.
// The cache controller never reads and refills on the same edge. Keep ADS
// read/write checking enabled; do not suppress collisions with no_rw_check.
module rv_icache_line_ram #(
    parameter SET_BITS = 6
)(
    input wire clk,
    input wire write_enable,
    input wire [SET_BITS-1:0] write_set,
    input wire [255:0] write_line,
    input wire read_enable,
    input wire [SET_BITS-1:0] read_set,
    output reg [255:0] read_line
);
    reg [255:0] mem [0:(1<<SET_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;
    always @(posedge clk) begin
        if (write_enable) mem[write_set] <= write_line;
        if (read_enable) read_line <= mem[read_set];
    end
endmodule
