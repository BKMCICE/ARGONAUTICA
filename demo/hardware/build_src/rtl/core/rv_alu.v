// rv_alu.v - 32-bit integer ALU + branch comparator
`include "rv_defs.vh"

module rv_alu (
    input  wire [3:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] y
);
    wire [4:0]  sh   = b[4:0];
    wire        lt   = ($signed(a) < $signed(b));
    wire        ltu  = (a < b);

    always @(*) begin
        case (op)
            `ALU_ADD:   y = a + b;
            `ALU_SUB:   y = a - b;
            `ALU_SLL:   y = a << sh;
            `ALU_SLT:   y = {31'b0, lt};
            `ALU_SLTU:  y = {31'b0, ltu};
            `ALU_XOR:   y = a ^ b;
            `ALU_SRL:   y = a >> sh;
            `ALU_SRA:   y = $signed(a) >>> sh;
            `ALU_OR:    y = a | b;
            `ALU_AND:   y = a & b;
            `ALU_PASSB: y = b;
            default:    y = a + b;
        endcase
    end
endmodule

// Branch condition evaluator (separate from ALU so target address and
// condition are computed in parallel in EX).
module rv_branch_cmp (
    input  wire [2:0]  branch,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg         taken
);
    wire eq  = (a == b);
    wire lt  = ($signed(a) < $signed(b));
    wire ltu = (a < b);
    always @(*) begin
        case (branch)
            `BR_BEQ:  taken = eq;
            `BR_BNE:  taken = ~eq;
            `BR_BLT:  taken = lt;
            `BR_BGE:  taken = ~lt;
            `BR_BLTU: taken = ltu;
            `BR_BGEU: taken = ~ltu;
            `BR_JUMP: taken = 1'b1;
            default:  taken = 1'b0;
        endcase
    end
endmodule
