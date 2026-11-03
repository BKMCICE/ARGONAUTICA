// rv_defs.vh - shared encodings for rv_core
// Include in every core module: `include "rv_defs.vh"
`ifndef RV_DEFS_VH
`define RV_DEFS_VH

// ---------------- opcodes (instr[6:0]) ----------------
`define OP_LOAD     7'b0000011
`define OP_MISCMEM  7'b0001111
`define OP_OPIMM    7'b0010011
`define OP_AUIPC    7'b0010111
`define OP_STORE    7'b0100011
`define OP_OP       7'b0110011
`define OP_LUI      7'b0110111
`define OP_BRANCH   7'b1100011
`define OP_JALR     7'b1100111
`define OP_JAL      7'b1101111
`define OP_SYSTEM   7'b1110011

// ---------------- ALU ops ----------------
`define ALU_ADD   4'd0
`define ALU_SUB   4'd1
`define ALU_SLL   4'd2
`define ALU_SLT   4'd3
`define ALU_SLTU  4'd4
`define ALU_XOR   4'd5
`define ALU_SRL   4'd6
`define ALU_SRA   4'd7
`define ALU_OR    4'd8
`define ALU_AND   4'd9
`define ALU_PASSB 4'd10   // LUI: result = operand B

// ALU operand A select
`define ALUA_RS1  2'd0
`define ALUA_PC   2'd1
`define ALUA_ZERO 2'd2
// ALU operand B select
`define ALUB_RS2  2'd0
`define ALUB_IMM  2'd1
`define ALUB_FOUR 2'd2

// ---------------- branch type ----------------
`define BR_NONE 3'd0
`define BR_BEQ  3'd1
`define BR_BNE  3'd2
`define BR_BLT  3'd3
`define BR_BGE  3'd4
`define BR_BLTU 3'd5
`define BR_BGEU 3'd6
`define BR_JUMP 3'd7   // JAL / JALR: always taken

// ---------------- memory op ----------------
`define MEM_NONE 4'd0
`define MEM_LB   4'd1
`define MEM_LH   4'd2
`define MEM_LW   4'd3
`define MEM_LBU  4'd4
`define MEM_LHU  4'd5
`define MEM_SB   4'd6
`define MEM_SH   4'd7
`define MEM_SW   4'd8

// ---------------- write-back select ----------------
`define WB_ALU 2'd0
`define WB_MEM 2'd1
`define WB_PC4 2'd2
`define WB_CSR 2'd3

// ---------------- CSR op ----------------
`define CSR_NONE 2'd0
`define CSR_RW   2'd1
`define CSR_RS   2'd2
`define CSR_RC   2'd3

// ---------------- system ops ----------------
`define SYS_NONE   3'd0
`define SYS_ECALL  3'd1
`define SYS_EBREAK 3'd2
`define SYS_MRET   3'd3
`define SYS_WFI    3'd4
`define SYS_FENCEI 3'd5

// ---------------- M extension ops (mul_op) ----------------
`define MUL_NONE   3'd0
`define MUL_MUL    3'd1
`define MUL_MULH   3'd2
`define MUL_MULHSU 3'd3
`define MUL_MULHU  3'd4
`define MUL_DIV    3'd5
`define MUL_DIVU   3'd6
`define MUL_REM    3'd7
// REMU is encoded as MUL_REM with the unsigned flag

// ---------------- mcause codes ----------------
`define EXC_IADDR_MISALIGN 4'd0
`define EXC_IACCESS_FAULT  4'd1
`define EXC_ILLEGAL        4'd2
`define EXC_BREAKPOINT     4'd3
`define EXC_LADDR_MISALIGN 4'd4
`define EXC_LACCESS_FAULT  4'd5
`define EXC_SADDR_MISALIGN 4'd6
`define EXC_SACCESS_FAULT  4'd7
`define EXC_ECALL_M        4'd11
`define IRQ_MSI 4'd3
`define IRQ_MTI 4'd7
`define IRQ_MEI 4'd11

// ---------------- CSR addresses ----------------
`define CSR_MSTATUS   12'h300
`define CSR_MISA      12'h301
`define CSR_MIE       12'h304
`define CSR_MTVEC     12'h305
`define CSR_MSCRATCH  12'h340
`define CSR_MEPC      12'h341
`define CSR_MCAUSE    12'h342
`define CSR_MTVAL     12'h343
`define CSR_MIP       12'h344
`define CSR_MCYCLE    12'hB00
`define CSR_MINSTRET  12'hB02
`define CSR_MCYCLEH   12'hB80
`define CSR_MINSTRETH 12'hB82
`define CSR_CYCLE     12'hC00
`define CSR_TIME      12'hC01
`define CSR_INSTRET   12'hC02
`define CSR_CYCLEH    12'hC80
`define CSR_TIMEH     12'hC81
`define CSR_INSTRETH  12'hC82
`define CSR_MVENDORID 12'hF11
`define CSR_MARCHID   12'hF12
`define CSR_MIMPID    12'hF13
`define CSR_MHARTID   12'hF14

`endif
