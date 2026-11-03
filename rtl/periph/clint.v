// clint.v - Core-Local Interruptor: 64-bit mtime, mtimecmp, msip.
//   0x00 MSIP      R/W [0]
//   0x08 MTIMECMP  lo, 0x0C hi
//   0x10 MTIME     lo, 0x14 hi
// (compact layout instead of the SiFive 0xBFF8/0x4000 offsets)
module clint (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready,
    output reg         msip,
    output reg         mtip
);
    assign ready = 1'b1;
    reg [63:0] mtime, mtimecmp;
    // registered compare: the 64-bit magnitude compare would otherwise sit
    // on the interrupt -> trap path (one cycle of latency is irrelevant)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mtip <= 1'b0;
        else        mtip <= (mtime >= mtimecmp);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime <= 64'b0; mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; msip <= 1'b0;
        end else begin
            mtime <= mtime + 64'd1;
            if (req && we) begin
                case (addr[4:2])
                    3'd0: msip <= wdata[0];
                    3'd2: mtimecmp[31:0]  <= wdata;
                    3'd3: mtimecmp[63:32] <= wdata;
                    3'd4: mtime[31:0]     <= wdata;
                    3'd5: mtime[63:32]    <= wdata;
                    default: ;
                endcase
            end
        end
    end
    always @(*) begin
        case (addr[4:2])
            3'd0: rdata = {31'b0, msip};
            3'd2: rdata = mtimecmp[31:0];
            3'd3: rdata = mtimecmp[63:32];
            3'd4: rdata = mtime[31:0];
            3'd5: rdata = mtime[63:32];
            default: rdata = 32'b0;
        endcase
    end
endmodule
