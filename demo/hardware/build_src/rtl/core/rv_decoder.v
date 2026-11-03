// rv_decoder.v - RV32I(M) instruction decoder (combinational)
// Produces the control word consumed by the EX/MEM/WB stages.
`include "rv_defs.vh"

module rv_decoder #(
    parameter ENABLE_M = 0
)(
    input  wire [31:0] instr,

    output reg  [4:0]  rs1,
    output reg  [4:0]  rs2,
    output reg  [4:0]  rd,
    output reg  [31:0] imm,
    output reg         rs1_used,     // for forwarding/hazard logic
    output reg         rs2_used,

    output reg  [3:0]  alu_op,
    output reg  [1:0]  alu_a_sel,
    output reg  [1:0]  alu_b_sel,
    output reg  [2:0]  branch,
    output reg  [3:0]  mem_op,
    output reg  [1:0]  wb_sel,
    output reg         reg_we,
    output reg  [1:0]  csr_op,
    output reg         csr_imm,      // CSRxxI: use zimm instead of rs1
    output reg  [11:0] csr_addr,
    output reg  [2:0]  sys_op,
    output reg  [2:0]  mul_op,
    output reg         mul_unsigned, // REMU (mul_op==MUL_REM && mul_unsigned)
    output reg         is_jalr,
    output reg         illegal
);

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    // immediates
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
    wire [31:0] imm_z = {27'b0, instr[19:15]};   // CSR zimm

    always @(*) begin
        rs1          = instr[19:15];
        rs2          = instr[24:20];
        rd           = instr[11:7];
        imm          = imm_i;
        rs1_used     = 1'b0;
        rs2_used     = 1'b0;
        alu_op       = `ALU_ADD;
        alu_a_sel    = `ALUA_RS1;
        alu_b_sel    = `ALUB_RS2;
        branch       = `BR_NONE;
        mem_op       = `MEM_NONE;
        wb_sel       = `WB_ALU;
        reg_we       = 1'b0;
        csr_op       = `CSR_NONE;
        csr_imm      = 1'b0;
        csr_addr     = instr[31:20];
        sys_op       = `SYS_NONE;
        mul_op       = `MUL_NONE;
        mul_unsigned = 1'b0;
        is_jalr      = 1'b0;
        illegal      = 1'b0;

        case (opcode)
        `OP_LUI: begin
            imm       = imm_u;
            alu_op    = `ALU_PASSB;
            alu_b_sel = `ALUB_IMM;
            reg_we    = 1'b1;
        end
        `OP_AUIPC: begin
            imm       = imm_u;
            alu_a_sel = `ALUA_PC;
            alu_b_sel = `ALUB_IMM;
            reg_we    = 1'b1;
        end
        `OP_JAL: begin
            imm       = imm_j;
            branch    = `BR_JUMP;
            alu_a_sel = `ALUA_PC;     // target = pc + imm
            alu_b_sel = `ALUB_IMM;
            wb_sel    = `WB_PC4;
            reg_we    = 1'b1;
        end
        `OP_JALR: begin
            imm       = imm_i;
            branch    = `BR_JUMP;
            is_jalr   = 1'b1;
            rs1_used  = 1'b1;
            alu_a_sel = `ALUA_RS1;    // target = (rs1 + imm) & ~1
            alu_b_sel = `ALUB_IMM;
            wb_sel    = `WB_PC4;
            reg_we    = 1'b1;
            if (funct3 != 3'b000) illegal = 1'b1;
        end
        `OP_BRANCH: begin
            imm       = imm_b;
            rs1_used  = 1'b1;
            rs2_used  = 1'b1;
            alu_a_sel = `ALUA_PC;     // ALU computes target; compare unit does the condition
            alu_b_sel = `ALUB_IMM;
            case (funct3)
                3'b000: branch = `BR_BEQ;
                3'b001: branch = `BR_BNE;
                3'b100: branch = `BR_BLT;
                3'b101: branch = `BR_BGE;
                3'b110: branch = `BR_BLTU;
                3'b111: branch = `BR_BGEU;
                default: illegal = 1'b1;
            endcase
        end
        `OP_LOAD: begin
            imm       = imm_i;
            rs1_used  = 1'b1;
            alu_b_sel = `ALUB_IMM;
            wb_sel    = `WB_MEM;
            reg_we    = 1'b1;
            case (funct3)
                3'b000: mem_op = `MEM_LB;
                3'b001: mem_op = `MEM_LH;
                3'b010: mem_op = `MEM_LW;
                3'b100: mem_op = `MEM_LBU;
                3'b101: mem_op = `MEM_LHU;
                default: illegal = 1'b1;
            endcase
        end
        `OP_STORE: begin
            imm       = imm_s;
            rs1_used  = 1'b1;
            rs2_used  = 1'b1;
            alu_b_sel = `ALUB_IMM;
            case (funct3)
                3'b000: mem_op = `MEM_SB;
                3'b001: mem_op = `MEM_SH;
                3'b010: mem_op = `MEM_SW;
                default: illegal = 1'b1;
            endcase
        end
        `OP_OPIMM: begin
            imm       = imm_i;
            rs1_used  = 1'b1;
            alu_b_sel = `ALUB_IMM;
            reg_we    = 1'b1;
            case (funct3)
                3'b000: alu_op = `ALU_ADD;
                3'b010: alu_op = `ALU_SLT;
                3'b011: alu_op = `ALU_SLTU;
                3'b100: alu_op = `ALU_XOR;
                3'b110: alu_op = `ALU_OR;
                3'b111: alu_op = `ALU_AND;
                3'b001: begin
                    alu_op = `ALU_SLL;
                    if (funct7 != 7'b0000000) illegal = 1'b1;
                end
                3'b101: begin
                    if (funct7 == 7'b0000000)      alu_op = `ALU_SRL;
                    else if (funct7 == 7'b0100000) alu_op = `ALU_SRA;
                    else illegal = 1'b1;
                end
                default: illegal = 1'b1;
            endcase
        end
        `OP_OP: begin
            rs1_used = 1'b1;
            rs2_used = 1'b1;
            reg_we   = 1'b1;
            if (funct7 == 7'b0000001) begin
                // M extension
                if (ENABLE_M) begin
                    case (funct3)
                        3'b000: mul_op = `MUL_MUL;
                        3'b001: mul_op = `MUL_MULH;
                        3'b010: mul_op = `MUL_MULHSU;
                        3'b011: mul_op = `MUL_MULHU;
                        3'b100: mul_op = `MUL_DIV;
                        3'b101: mul_op = `MUL_DIVU;
                        3'b110: mul_op = `MUL_REM;
                        3'b111: begin mul_op = `MUL_REM; mul_unsigned = 1'b1; end
                    endcase
                end else begin
                    illegal = 1'b1;
                end
            end else begin
                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000)      alu_op = `ALU_ADD;
                        else if (funct7 == 7'b0100000) alu_op = `ALU_SUB;
                        else illegal = 1'b1;
                    end
                    3'b001: begin alu_op = `ALU_SLL;  if (funct7 != 7'b0) illegal = 1'b1; end
                    3'b010: begin alu_op = `ALU_SLT;  if (funct7 != 7'b0) illegal = 1'b1; end
                    3'b011: begin alu_op = `ALU_SLTU; if (funct7 != 7'b0) illegal = 1'b1; end
                    3'b100: begin alu_op = `ALU_XOR;  if (funct7 != 7'b0) illegal = 1'b1; end
                    3'b101: begin
                        if (funct7 == 7'b0000000)      alu_op = `ALU_SRL;
                        else if (funct7 == 7'b0100000) alu_op = `ALU_SRA;
                        else illegal = 1'b1;
                    end
                    3'b110: begin alu_op = `ALU_OR;   if (funct7 != 7'b0) illegal = 1'b1; end
                    3'b111: begin alu_op = `ALU_AND;  if (funct7 != 7'b0) illegal = 1'b1; end
                endcase
            end
        end
        `OP_MISCMEM: begin
            // FENCE (funct3=000) -> NOP ; FENCE.I (funct3=001) -> flush front-end
            case (funct3)
                3'b000: sys_op = `SYS_NONE;
                3'b001: sys_op = `SYS_FENCEI;
                default: illegal = 1'b1;
            endcase
        end
        `OP_SYSTEM: begin
            if (funct3 == 3'b000) begin
                // ECALL / EBREAK / MRET / WFI
                case (instr[31:20])
                    12'h000: sys_op = `SYS_ECALL;
                    12'h001: sys_op = `SYS_EBREAK;
                    12'h302: sys_op = `SYS_MRET;
                    12'h105: sys_op = `SYS_WFI;
                    default: illegal = 1'b1;
                endcase
                if (instr[19:7] != 13'b0) illegal = 1'b1;
            end else if (funct3 == 3'b100) begin
                illegal = 1'b1;
            end else begin
                // CSR ops
                imm      = imm_z;
                csr_imm  = funct3[2];
                rs1_used = ~funct3[2];
                wb_sel   = `WB_CSR;
                reg_we   = 1'b1;
                case (funct3[1:0])
                    2'b01: csr_op = `CSR_RW;
                    2'b10: csr_op = `CSR_RS;
                    2'b11: csr_op = `CSR_RC;
                    default: illegal = 1'b1;
                endcase
            end
        end
        default: illegal = 1'b1;
        endcase

        // rd = x0 never writes (keeps hazard logic simple)
        if (rd == 5'd0) reg_we = 1'b0;
    end
endmodule
