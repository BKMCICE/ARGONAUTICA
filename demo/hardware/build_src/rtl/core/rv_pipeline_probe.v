// Diagnostic observer only. All fields are delayed by one common clk edge.
// No output feeds CPU control. PC is exact only when sample_q[14] is asserted.
module rv_pipeline_probe (
    input wire clk,
    input wire rst_n,
    input wire [31:0] mem_pc,
    input wire [10:0] flags,
    // ADS: preserve unused observation registers until the FIC inserts a load.
    (* syn_preserve = 1, syn_noprune = 1 *) output reg [25:0] sample_q
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sample_q <= 26'b0;
        else sample_q <= {flags, (mem_pc[31:16] == 16'b0), mem_pc[15:2]};
    end
endmodule
