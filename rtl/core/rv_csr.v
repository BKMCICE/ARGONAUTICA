// rv_csr.v - Machine-mode CSR file, trap entry/return, interrupt pending logic.
// All writes happen from the MEM stage (commit point).
`include "rv_defs.vh"

module rv_csr #(
    parameter ENABLE_M = 0
)(
    input  wire        clk,
    input  wire        rst_n,

    // read port (EX stage computes new value; read value also used for rd)
    input  wire [11:0] raddr,
    output reg  [31:0] rdata,
    output wire        raddr_illegal,

    // write port (MEM stage)
    input  wire        we,
    input  wire [11:0] waddr,
    input  wire [31:0] wdata,

    // trap / mret (MEM stage)
    input  wire        trap_enter,
    input  wire        trap_is_irq,
    input  wire [3:0]  trap_cause,
    input  wire [31:0] trap_pc,      // value written to mepc
    input  wire [31:0] trap_val,     // value written to mtval
    input  wire        mret,
    output wire [31:0] trap_vector,  // where to jump on trap
    output wire [31:0] mepc_out,

    // interrupt lines
    input  wire        irq_software,
    input  wire        irq_timer,
    input  wire        irq_external,
    output wire        irq_pending,  // any enabled + pending interrupt
    output wire [3:0]  irq_cause,

    // counters
    input  wire        instr_retired
);
    // ---------------- registers ----------------
    reg        mstatus_mie, mstatus_mpie;
    reg [31:0] mtvec;
    reg [31:0] mscratch;
    reg [31:0] mepc;
    reg [31:0] mcause;
    reg [31:0] mtval;
    reg        mie_msie, mie_mtie, mie_meie;
    reg [63:0] mcycle;
    reg [63:0] minstret;

    wire [31:0] mstatus = {19'b0, 2'b11 /*MPP*/, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
    wire [31:0] mie     = {20'b0, mie_meie, 3'b0, mie_mtie, 3'b0, mie_msie, 3'b0};
    wire [31:0] mip     = {20'b0, irq_external, 3'b0, irq_timer, 3'b0, irq_software, 3'b0};
    wire [31:0] misa    = 32'h4000_0000 | 32'h0000_0100 | (ENABLE_M ? 32'h0000_1000 : 32'h0);

    assign mepc_out = mepc;
    // direct mode: base; vectored mode: base + 4*cause for interrupts
    assign trap_vector = (mtvec[1:0] == 2'b01 && trap_is_irq) ?
                         ({mtvec[31:2], 2'b0} + {26'b0, trap_cause, 2'b0}) :
                         {mtvec[31:2], 2'b0};

    // ---------------- interrupt priority: MEI > MSI > MTI ----------------
    wire mei = irq_external & mie_meie;
    wire msi = irq_software & mie_msie;
    wire mti = irq_timer    & mie_mtie;
    assign irq_pending = mstatus_mie & (mei | msi | mti);
    assign irq_cause   = mei ? `IRQ_MEI : msi ? `IRQ_MSI : `IRQ_MTI;

    // ---------------- read ----------------
    reg rd_ok;
    assign raddr_illegal = ~rd_ok;
    always @(*) begin
        rd_ok = 1'b1;
        rdata = 32'b0;
        case (raddr)
            `CSR_MSTATUS:   rdata = mstatus;
            `CSR_MISA:      rdata = misa;
            `CSR_MIE:       rdata = mie;
            `CSR_MTVEC:     rdata = mtvec;
            `CSR_MSCRATCH:  rdata = mscratch;
            `CSR_MEPC:      rdata = mepc;
            `CSR_MCAUSE:    rdata = mcause;
            `CSR_MTVAL:     rdata = mtval;
            `CSR_MIP:       rdata = mip;
            `CSR_MCYCLE,   `CSR_CYCLE:    rdata = mcycle[31:0];
            `CSR_MCYCLEH,  `CSR_CYCLEH:   rdata = mcycle[63:32];
            `CSR_MINSTRET, `CSR_INSTRET:  rdata = minstret[31:0];
            `CSR_MINSTRETH,`CSR_INSTRETH: rdata = minstret[63:32];
            `CSR_TIME:      rdata = mcycle[31:0];
            `CSR_TIMEH:     rdata = mcycle[63:32];
            `CSR_MVENDORID, `CSR_MARCHID, `CSR_MIMPID, `CSR_MHARTID: rdata = 32'b0;
            default: rd_ok = 1'b0;
        endcase
    end

    // ---------------- write / trap / counters ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
            mtvec        <= 32'b0;
            mscratch     <= 32'b0;
            mepc         <= 32'b0;
            mcause       <= 32'b0;
            mtval        <= 32'b0;
            mie_msie     <= 1'b0;
            mie_mtie     <= 1'b0;
            mie_meie     <= 1'b0;
            mcycle       <= 64'b0;
            minstret     <= 64'b0;
        end else begin
            mcycle <= mcycle + 64'd1;
            // A write to either half of minstret suppresses this instruction's
            // increment for the entire 64-bit counter (including carry).
            if (instr_retired && !(we && (waddr == `CSR_MINSTRET ||
                                          waddr == `CSR_MINSTRETH)))
                minstret <= minstret + 64'd1;

            if (trap_enter) begin
                mepc         <= {trap_pc[31:2], 2'b0};
                mcause       <= {trap_is_irq, 27'b0, trap_cause};
                mtval        <= trap_val;
                mstatus_mpie <= mstatus_mie;
                mstatus_mie  <= 1'b0;
            end else if (mret) begin
                mstatus_mie  <= mstatus_mpie;
                mstatus_mpie <= 1'b1;
            end else if (we) begin
                case (waddr)
                    `CSR_MSTATUS: begin
                        mstatus_mie  <= wdata[3];
                        mstatus_mpie <= wdata[7];
                    end
                    `CSR_MIE: begin
                        mie_msie <= wdata[3];
                        mie_mtie <= wdata[7];
                        mie_meie <= wdata[11];
                    end
                    `CSR_MTVEC:     mtvec    <= {wdata[31:2], 1'b0, wdata[0]};
                    `CSR_MSCRATCH:  mscratch <= wdata;
                    `CSR_MEPC:      mepc     <= {wdata[31:2], 2'b0};
                    `CSR_MCAUSE:    mcause   <= wdata;
                    `CSR_MTVAL:     mtval    <= wdata;
                    `CSR_MCYCLE:    mcycle[31:0]    <= wdata;
                    `CSR_MCYCLEH:   mcycle[63:32]   <= wdata;
                    `CSR_MINSTRET:  minstret[31:0]  <= wdata;
                    `CSR_MINSTRETH: minstret[63:32] <= wdata;
                    default: ;
                endcase
            end
        end
    end
endmodule
