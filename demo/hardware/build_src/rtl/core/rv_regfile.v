// rv_regfile.v - 32 x 32-bit register file, 2R1W, write-first bypass.
// x0 is hard-wired to zero. Implemented with registers (LUT RAM / FFs)
// so that the read is asynchronous and the write-first bypass is trivial.
module rv_regfile #(
    parameter STORAGE = 0 // 0: original asynchronous LUT RAM, 1: explicit FFs
)(
    input  wire        clk,
    input  wire [4:0]  raddr1,
    output wire [31:0] rdata1,
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata2,
    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata
);
    // lut_ram: keep the read asynchronous so the ID/EX flop stays a real
    // pipeline register (PDS otherwise folds the array into a DRM whose 2.3 ns
    // clock-to-out lands on the EX critical path).
    reg [31:0] regs [1:31] /* synthesis syn_ramstyle="lut_ram" */;
    integer i;
    initial begin
        for (i = 1; i < 32; i = i + 1) regs[i] = 32'b0;
    end

    always @(posedge clk) begin
        if (STORAGE == 0 && we && waddr != 5'd0) regs[waddr] <= wdata;
    end

    wire [31:0] raw1, raw2;
    generate if (STORAGE == 1) begin : ff_storage
        // Keep the asynchronous 2R1W contract, including configuration-time
        // zero initialization. No reset port or extra pipeline stage.
        reg [31:0] words [1:31] /* synthesis syn_ramstyle="registers" */;
        integer word_index;
        initial begin
            for (word_index = 1; word_index < 32; word_index = word_index + 1)
                words[word_index] = 32'b0;
        end
        always @(posedge clk)
            if (we && waddr != 5'd0) words[waddr] <= wdata;
        assign raw1 = words[raddr1];
        assign raw2 = words[raddr2];
    end else begin : original_storage
        assign raw1 = regs[raddr1];
        assign raw2 = regs[raddr2];
    end endgenerate

    wire byp1 = we && (waddr != 5'd0) && (waddr == raddr1);
    wire byp2 = we && (waddr != 5'd0) && (waddr == raddr2);

    assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : (byp1 ? wdata : raw1);
    assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : (byp2 ? wdata : raw2);
`ifndef SYNTHESIS
    initial if (STORAGE != 0 && STORAGE != 1)
        $fatal(1, "rv_regfile STORAGE must be 0 or 1");
`endif
endmodule
