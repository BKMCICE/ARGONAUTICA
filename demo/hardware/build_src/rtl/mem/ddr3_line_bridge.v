// Converts one 32-byte cache-line transaction into one native 256-bit beat of
// the Pango Logos HMIC_S DDR3 user interface. All signals share its UI clock.
// Cache addresses 0x8000_0000..0xBFFF_FFFF map to DDR word addresses 0..
// The controller's address unit is 32-bit words (8 words per 256-bit beat).
module ddr3_line_bridge (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         ddr_init_done,
    input  wire         line_req,
    input  wire         line_we,
    input  wire [31:0]  line_addr,
    input  wire [255:0] line_wdata,
    output reg  [255:0] line_rdata,
    output wire         line_ready,
    output wire [27:0]  axi_awaddr,
    output wire         axi_awuser_ap,
    output wire [3:0]   axi_awuser_id,
    output wire [3:0]   axi_awlen,
    input  wire         axi_awready,
    output wire         axi_awvalid,
    output wire [255:0] axi_wdata,
    output wire [31:0]  axi_wstrb,
    input  wire         axi_wready,
    output wire [27:0]  axi_araddr,
    output wire         axi_aruser_ap,
    output wire [3:0]   axi_aruser_id,
    output wire [3:0]   axi_arlen,
    input  wire         axi_arready,
    output wire         axi_arvalid,
    input  wire [255:0] axi_rdata,
    input  wire         axi_rvalid,
    input  wire         axi_rlast
);
    localparam IDLE = 3'd0, WRITE_ADDR = 3'd1, WRITE_DATA = 3'd2;
    localparam READ_ADDR = 3'd3, READ_DATA = 3'd4, RESP = 3'd5;
    reg [2:0] state;
    reg [31:0] held_addr;
    reg [255:0] held_wdata;

    assign line_ready = state == RESP;
    assign axi_awaddr = held_addr[29:2];
    assign axi_araddr = held_addr[29:2];
    assign axi_awuser_ap = 1'b0;
    assign axi_aruser_ap = 1'b0;
    assign axi_awuser_id = 4'b0;
    assign axi_aruser_id = 4'b0;
    assign axi_awlen = 4'd0;
    assign axi_arlen = 4'd0;
    assign axi_awvalid = state == WRITE_ADDR;
    assign axi_arvalid = state == READ_ADDR;
    assign axi_wdata = held_wdata;
    assign axi_wstrb = 32'hFFFF_FFFF;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            held_addr <= 0;
            held_wdata <= 0;
            line_rdata <= 0;
        end else begin
            case (state)
                IDLE: if (ddr_init_done && line_req) begin
                    held_addr <= {line_addr[31:5], 5'b0};
                    held_wdata <= line_wdata;
                    state <= line_we ? WRITE_ADDR : READ_ADDR;
                end
                WRITE_ADDR: if (axi_awready) state <= WRITE_DATA;
                WRITE_DATA: if (axi_wready) state <= RESP;
                READ_ADDR: if (axi_arready) state <= READ_DATA;
                READ_DATA: if (axi_rvalid && axi_rlast) begin
                    line_rdata <= axi_rdata;
                    state <= RESP;
                end
                RESP: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
