// A61 test-only copy: configurable read latency, identical native protocol/data model.
// Simple 256-bit native DDR model for SoC simulation, indexed by word address.
module ddr3_native_latency_model #(
    parameter READ_WAIT = 3,
    parameter LINE_ADDR_BITS = 11
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [27:0]  axi_awaddr,
    input  wire [3:0]   axi_awlen,
    input  wire         axi_awvalid,
    output wire         axi_awready,
    input  wire [255:0] axi_wdata,
    input  wire [31:0]  axi_wstrb,
    output wire         axi_wready,
    input  wire [27:0]  axi_araddr,
    input  wire [3:0]   axi_arlen,
    input  wire         axi_arvalid,
    output wire         axi_arready,
    output reg  [255:0] axi_rdata,
    output wire         axi_rvalid,
    output wire         axi_rlast
);
    localparam LINE_COUNT = 1 << LINE_ADDR_BITS;
    reg [255:0] mem [0:LINE_COUNT-1];
    reg wr_active, rd_active;
    reg [2:0] wr_count;
    reg [7:0] rd_count;
    reg [27:0] wr_addr, rd_addr;
    integer i, b;
    reg [1023:0] ddr_hexfile;
    initial begin
        for (i = 0; i < LINE_COUNT; i = i + 1) mem[i] = 0;
        if ($value$plusargs("ddr_hex=%s", ddr_hexfile)) $readmemh(ddr_hexfile, mem);
    end
    assign axi_awready = !wr_active;
    assign axi_arready = !rd_active;
    assign axi_wready = wr_active && wr_count == 0;
    assign axi_rvalid = rd_active && rd_count == 0;
    assign axi_rlast = axi_rvalid;
    always @(*) axi_rdata = mem[rd_addr[LINE_ADDR_BITS+2:3]];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_active <= 0;
            rd_active <= 0;
            wr_count <= 0;
            rd_count <= 0;
            wr_addr <= 0;
            rd_addr <= 0;
        end else begin
            if (axi_awvalid && axi_awready) begin
                if (axi_awlen != 0 || axi_awaddr[2:0] != 0) $fatal(1, "write burst shape");
                wr_active <= 1;
                wr_count <= 2;
                wr_addr <= axi_awaddr;
            end else if (wr_active && wr_count != 0) wr_count <= wr_count - 1;
            else if (axi_wready) begin
                for (b = 0; b < 32; b = b + 1)
                    if (axi_wstrb[b]) mem[wr_addr[LINE_ADDR_BITS+2:3]][b*8 +: 8] <= axi_wdata[b*8 +: 8];
                wr_active <= 0;
            end
            if (axi_arvalid && axi_arready) begin
                if (axi_arlen != 0 || axi_araddr[2:0] != 0) $fatal(1, "read burst shape");
                rd_active <= 1;
                rd_count <= READ_WAIT;
                rd_addr <= axi_araddr;
            end else if (rd_active && rd_count != 0) rd_count <= rd_count - 1;
            else if (axi_rvalid) rd_active <= 0;
        end
    end
endmodule
