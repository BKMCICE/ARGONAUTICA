// perf_counter.v - 32-bit event counters for the performance report.
//   0x00 CTRL : [0] enable [1] clear (W)
//   0x04.. one 32-bit counter per event, read-only:
//     0x04 cycles, 0x08 instr, 0x0C branches, 0x10 mispredicts,
//     0x14 load-use stalls, 0x18 imem stalls, 0x1C dmem stalls, 0x20 traps
module perf_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready,
    input  wire [7:0]  events      // {trap, dmem, imem, ld_use, mispred, branch, instr, 1'b1}
);
    assign ready = 1'b1;
    reg        en;
    reg [31:0] cnt [0:7];
    integer i;
    wire clr = req & we & (addr[5:2] == 4'd0) & wdata[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en <= 1'b0;
            for (i = 0; i < 8; i = i + 1) cnt[i] <= 32'b0;
        end else begin
            if (req && we && addr[5:2] == 4'd0) en <= wdata[0];
            for (i = 0; i < 8; i = i + 1) begin
                if (clr)              cnt[i] <= 32'b0;
                else if (en && events[i]) cnt[i] <= cnt[i] + 32'd1;
            end
        end
    end
    always @(*) begin
        if (addr[5:2] == 4'd0)      rdata = {31'b0, en};
        else if (addr[5:2] <= 4'd8) rdata = cnt[addr[5:2] - 4'd1];
        else                        rdata = 32'b0;
    end
endmodule
