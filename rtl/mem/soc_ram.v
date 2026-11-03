// soc_ram.v - byte-writable 32-bit RAM with independent instruction and data
// ports (true dual-port), synchronous read on both ports. Maps onto Logos
// DRM18K blocks. Optional $readmemh init for simulation / boot ROM.
//
// Port A (instruction): read-only, data valid the cycle after req.
// Port B (data): read/write. To keep the core's MEM stage single-cycle we
// register the request and complete it on the following cycle
// (ready is a 1-cycle-late pulse), i.e. every data access costs 2 cycles.
// The rv_core MEM stage holds until ready.
module soc_ram #(
    parameter ADDR_WIDTH = 14,          // words -> 2^14 words = 64 KB
    parameter INIT_FILE  = ""
)(
    input  wire                  clk,
    input  wire                  rst_n,
    // instruction port
    input  wire                  i_req,
    input  wire [31:0]           i_addr,
    output reg  [31:0]           i_rdata,
    output reg                   i_ready,
    output reg                   i_fault,
    // data port
    input  wire                  d_req,
    input  wire                  d_we,
    input  wire [3:0]            d_be,
    input  wire [31:0]           d_addr,
    input  wire [31:0]           d_wdata,
    output reg  [31:0]           d_rdata,
    output reg                   d_ready
);
    localparam DEPTH = 1 << ADDR_WIDTH;
    reg [31:0] mem [0:DEPTH-1];

    // Simulation-only init (PDS synthesis rejects the 64K-iteration loop and
    // DRM blocks power up to zero anyway); the boot image comes from INIT_FILE.
`ifndef SYNTHESIS
    integer k;
    initial begin
        for (k = 0; k < DEPTH; k = k + 1) mem[k] = 32'h0000_0013;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end
`else
    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end
`endif

    wire [ADDR_WIDTH-1:0] ia = i_addr[ADDR_WIDTH+1:2];
    wire [ADDR_WIDTH-1:0] da = d_addr[ADDR_WIDTH+1:2];
    wire i_in_range = (i_addr[31:ADDR_WIDTH+2] == 0);
    wire d_in_range = (d_addr[31:ADDR_WIDTH+2] == 0);

    // instruction port
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_ready <= 1'b0;
            i_fault <= 1'b0;
        end else begin
            i_ready <= i_req;
            i_fault <= i_req && !i_in_range;
        end
    end
    always @(posedge clk) begin
        if (i_req) i_rdata <= i_in_range ? mem[ia] : 32'h0;
    end

    // data port: accept on cycle 0, respond on cycle 1
    reg d_pending;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_pending <= 1'b0;
            d_ready   <= 1'b0;
        end else begin
            d_ready   <= d_req & ~d_pending;   // 1-cycle pulse
            d_pending <= d_req & ~d_pending & ~d_ready;
        end
    end
    always @(posedge clk) begin
        if (d_req && !d_pending) begin
            if (d_we && d_in_range) begin
                if (d_be[0]) mem[da][7:0]   <= d_wdata[7:0];
                if (d_be[1]) mem[da][15:8]  <= d_wdata[15:8];
                if (d_be[2]) mem[da][23:16] <= d_wdata[23:16];
                if (d_be[3]) mem[da][31:24] <= d_wdata[31:24];
            end
            d_rdata <= d_in_range ? mem[da] : 32'hDEAD_BEEF;
        end
    end
endmodule
