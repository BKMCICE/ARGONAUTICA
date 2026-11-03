// rv_muldiv.v - RV32M multiplier / divider unit.
// MUL*: 1-cycle issue, 2-cycle pipelined result using a signed 33x33 multiply
//       (maps onto the Logos APM 18x18 blocks as a cascaded multiplier).
// DIV*: 32-cycle restoring divider (CoreMark barely uses division).
// Handshake: `start` for one cycle with operands stable until `done`.
`include "rv_defs.vh"

module rv_muldiv (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [2:0]  op,
    input  wire        op_unsigned,   // REMU
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg         done,
    output reg  [31:0] result
);
    // ---------------- multiply (3-stage: operand regs -> APM product -> select) ----------------
    // The APM cascade for a 33x33 product is ~9 ns on PGL50H-6, so operands are
    // registered first to keep the regfile->forward-mux->APM path off the
    // critical path. Result valid 3 cycles after start.
    wire a_signed = (op == `MUL_MULH) || (op == `MUL_MULHSU);
    wire b_signed = (op == `MUL_MULH);
    reg  signed [32:0] ma_r, mb_r;
    reg  signed [65:0] prod_r;
    reg  [2:0]  mul_op_r1, mul_op_r2;
    reg         mul_v1, mul_v2, mul_v3;
    wire is_mul = (op == `MUL_MUL) || (op == `MUL_MULH) || (op == `MUL_MULHSU) || (op == `MUL_MULHU);

    always @(posedge clk) begin
        ma_r      <= {a_signed & a[31], a};
        mb_r      <= {b_signed & b[31], b};
        mul_op_r1 <= op;
        prod_r    <= ma_r * mb_r;
        mul_op_r2 <= mul_op_r1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin mul_v1 <= 1'b0; mul_v2 <= 1'b0; mul_v3 <= 1'b0; end
        else begin
            mul_v1 <= start & is_mul;
            mul_v2 <= mul_v1;
            mul_v3 <= mul_v2;
        end
    end

    // ---------------- divide ----------------
    reg         div_busy;
    reg  [5:0]  div_cnt;
    reg  [31:0] dividend, divisor, quotient;
    reg  [32:0] remainder;
    reg         div_neg_q, div_neg_r, div_is_rem;
    wire is_div = (op == `MUL_DIV) || (op == `MUL_DIVU) || (op == `MUL_REM);
    wire div_signed = (op == `MUL_DIV) || ((op == `MUL_REM) && !op_unsigned);
    wire [31:0] abs_a = (div_signed && a[31]) ? -a : a;
    wire [31:0] abs_b = (div_signed && b[31]) ? -b : b;
    wire [32:0] sub   = {remainder[31:0], dividend[31]} - {1'b0, divisor};

    reg div_done;
    reg [31:0] div_result;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_busy <= 1'b0; div_cnt <= 6'd0; div_done <= 1'b0;
            dividend <= 0; divisor <= 0; quotient <= 0; remainder <= 0;
            div_neg_q <= 0; div_neg_r <= 0; div_is_rem <= 0; div_result <= 0;
        end else begin
            div_done <= 1'b0;
            if (start && is_div && !div_busy) begin
                div_busy   <= 1'b1;
                div_cnt    <= 6'd0;
                dividend   <= abs_a;
                divisor    <= abs_b;
                quotient   <= 32'b0;
                remainder  <= 33'b0;
                div_is_rem <= (op == `MUL_REM);
                div_neg_q  <= div_signed && (a[31] ^ b[31]) && (b != 0);
                div_neg_r  <= div_signed && a[31];
            end else if (div_busy) begin
                if (sub[32]) begin
                    remainder <= {remainder[31:0], dividend[31]};
                    quotient  <= {quotient[30:0], 1'b0};
                end else begin
                    remainder <= sub;
                    quotient  <= {quotient[30:0], 1'b1};
                end
                dividend <= {dividend[30:0], 1'b0};
                div_cnt  <= div_cnt + 6'd1;
                if (div_cnt == 6'd31) begin
                    div_busy <= 1'b0;
                    div_done <= 1'b1;
                end
            end
        end
    end
    // final fix-up (one cycle after last step); divide-by-zero per spec:
    // quotient = -1 (all ones), remainder = dividend.
    wire [31:0] q_fin = sub[32] ? {quotient[30:0], 1'b0} : {quotient[30:0], 1'b1};
    wire [32:0] r_fin = sub[32] ? {remainder[31:0], dividend[31]} : sub;
    reg  [31:0] q_r, r_r;
    reg         dbz_r;
    always @(posedge clk) begin
        if (div_busy && div_cnt == 6'd31) begin
            q_r   <= q_fin;
            r_r   <= r_fin[31:0];
            dbz_r <= (divisor == 32'b0);
        end
    end
    wire [31:0] q_signed = div_neg_q ? -q_r : q_r;
    wire [31:0] r_signed = div_neg_r ? -r_r : r_r;
    wire [31:0] div_out  = dbz_r ? (div_is_rem ? (div_neg_r ? -r_r : r_r) : 32'hFFFF_FFFF)
                                 : (div_is_rem ? r_signed : q_signed);

    // ---------------- output mux ----------------
    always @(*) begin
        done   = mul_v3 | div_done;
        result = 32'b0;
        if (mul_v3) begin
            case (mul_op_r2)
                `MUL_MUL: result = prod_r[31:0];
                default:  result = prod_r[63:32];
            endcase
        end else if (div_done) begin
            result = div_out;
        end
    end
endmodule
