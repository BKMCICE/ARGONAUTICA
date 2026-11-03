// rv_core.v - RV32I(M) 5-stage in-order pipeline: IF -> ID -> EX -> MEM -> WB
// See docs/pipeline_spec.md for the contract this file implements.
`include "rv_defs.vh"

module rv_core #(
    parameter [31:0] RESET_PC    = 32'h0000_0000,
    parameter        ENABLE_M    = 0,
    parameter        ENABLE_BTB  = 0,
    parameter        ENABLE_CACHE_FENCE = 0,
    parameter        BTB_ENTRIES = 32,
    parameter        REGFILE_STORAGE = 0,
    parameter        ENABLE_PIPELINE_PROBE = 0
)(
    input  wire        clk,
    input  wire        rst_n,

    // instruction port (synchronous-RAM semantics)
    output wire        imem_req,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    input  wire        imem_ready,
    input  wire        imem_fault,

    // data port
    output wire        dmem_req,
    output wire        dmem_we,
    output wire [3:0]  dmem_be,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,
    input  wire        dmem_ready,
    input  wire        dmem_fault,

    // interrupts
    input  wire        irq_software,
    input  wire        irq_timer,
    input  wire        irq_external,

    // performance events (1-cycle pulses)
    output wire        ev_instr_retired,
    output wire        ev_branch,
    output wire        ev_branch_mispred,
    output wire        ev_load_use_stall,
    output wire        ev_imem_stall,
    output wire        ev_dmem_stall,
    output wire        ev_trap,
    output wire        fetch_flush,
    output wire        fencei_req,
    input  wire        fencei_done,
    // ADS requires literal attributes on a port to retain an unloaded bank.
    // Only the explicitly enabled diagnostic build defines this macro.
`ifdef RV32_PIPELINE_PROBE_KEEP
    (* syn_preserve = 1, syn_noprune = 1 *)
`endif
    output reg [25:0] pipeline_probe_q
);

    // =====================================================================
    // Global pipeline control
    // =====================================================================
    // A memory stall freezes the whole pipeline.
    wire mem_stall;          // MEM waiting for dmem_ready
    wire if_stall;           // IF waiting for imem_ready
    wire ld_use_stall;       // ID must wait one cycle for a load in EX
    wire csr_stall;          // ID waits for CSR write in flight
    wire muldiv_stall;       // EX waiting for muldiv result
    wire ex_redirect;        // EX: branch/jump mispredict
    wire mem_redirect;       // MEM: trap / mret / fence.i
    wire id_bubble;
    wire [31:0] ex_redirect_pc;
    wire [31:0] mem_redirect_pc;

    wire fencei_wait;
    wire pipe_freeze = mem_stall | muldiv_stall | fencei_wait;
    // stage advance enables
    wire if_adv  = ~pipe_freeze & ~ld_use_stall & ~csr_stall & ~if_stall;
    wire id_adv  = ~pipe_freeze;                  // ID/EX register loads (bubble when stalled)
    wire ex_adv  = ~pipe_freeze;
    wire mem_adv = ~pipe_freeze;

    // =====================================================================
    // IF stage
    // =====================================================================
    reg  [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd4;
    wire        btb_hit;
    wire [31:0] btb_target;
    wire [31:0] pc_next_seq = (ENABLE_BTB && btb_hit) ? btb_target : pc_plus4;
    wire [31:0] pc_next = mem_redirect ? mem_redirect_pc :
                          ex_redirect  ? ex_redirect_pc  :
                          pc_next_seq;

    // Fetch protocol: a request is issued (imem_req) in every cycle the
    // front-end advances; the memory returns the word for that address in a
    // later cycle flagged by imem_ready (1 cycle for on-chip RAM, more for a
    // cache miss). The memory must latch the address on the request cycle.
    // A 1-entry skid captures the returned instruction so IF/ID can be held
    // while ID stalls.
    assign imem_addr = pc;

    reg         if_valid;      // an instruction fetch for `pc_r` is in flight
    reg  [31:0] pc_r;          // pc of the instruction being returned this cycle
    reg         pred_taken_r;
    reg  [31:0] pred_target_r;

    // when the front-end is redirected, the in-flight fetch is discarded
    wire if_kill = ex_redirect | mem_redirect;
    assign fetch_flush = if_kill;
    // Issue the fetch whenever the front-end advances, independent of the
    // redirect signals (a redirect simply drops the returning word via
    // if_valid<=0). Keeps the branch-resolve path off the RAM enable.
    assign imem_req = if_adv;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc       <= RESET_PC;
            pc_r     <= RESET_PC;
            if_valid <= 1'b0;
        end else begin
            if (mem_redirect || ex_redirect) begin
                pc       <= pc_next;
                if_valid <= 1'b0;   // discard whatever is returning
            end else if (if_adv) begin
                pc       <= pc_next;
                pc_r     <= pc;
                if_valid <= 1'b1;
            end else if (if_stall) begin
                // waiting on imem_ready: keep everything
            end
            // ld_use/csr stall with if_valid: hold pc, IF/ID re-latches same data
        end
    end

    // Prediction metadata is observed only when if_valid is set. Capture it
    // independently of a simultaneous redirect: that request is discarded,
    // and this keeps the EX redirect path out of these registers' enables.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pred_taken_r <= 1'b0;
            pred_target_r <= 32'b0;
        end else if (if_adv) begin
            pred_taken_r <= ENABLE_BTB && btb_hit;
            pred_target_r <= btb_target;
        end
    end

    // ---- IF/ID register ----
    reg         ifid_valid;
    reg         ifid_ifault;
    reg  [31:0] ifid_pc;
    reg  [31:0] ifid_instr;
    reg         ifid_pred_taken;
    reg  [31:0] ifid_pred_target;

    // instruction skid: imem_rdata is only valid on the ready cycle; if ID
    // is stalled we must keep it.
    reg         skid_valid;
    reg  [31:0] skid_instr;
    reg         skid_fault;
    // stall only while the fetched word has not arrived AND is not already
    // parked in the skid (otherwise a data-side freeze deadlocks the front-end)
    assign if_stall = if_valid & ~imem_ready & ~skid_valid;
    wire [31:0] if_instr = skid_valid ? skid_instr : imem_rdata;
    wire        if_fault = skid_valid ? skid_fault : imem_fault;
    wire        if_instr_valid = if_valid & (imem_ready | skid_valid);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skid_valid <= 1'b0;
        end else if (if_kill) begin
            skid_valid <= 1'b0;
        end else if (if_valid && imem_ready && !skid_valid && !if_adv) begin
            skid_valid <= 1'b1;      // data arrived but ID can't take it
        end else if (if_adv) begin
            skid_valid <= 1'b0;
        end
    end

    // Data captured on a killed or immediately consumed response is harmless;
    // skid_valid remains clear. This keeps branch/trap control off the enable
    // of all 32 skid payload bits.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) skid_instr <= 32'b0;
        else if (if_valid && imem_ready && !skid_valid)
            skid_instr <= imem_rdata;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) skid_fault <= 1'b0;
        else if (if_valid && imem_ready && !skid_valid)
            skid_fault <= imem_fault;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifid_valid <= 1'b0;
        end else if (if_kill) begin
            ifid_valid <= 1'b0;
        end else if (if_adv) begin
            ifid_valid <= if_instr_valid;
        end else if (id_adv && !id_bubble) begin
            // A delayed instruction fetch can leave IF/ID held for many
            // cycles. Consume its instruction once, then leave a bubble until
            // a new fetched word arrives.
            ifid_valid <= 1'b0;
        end
    end
    // The payload has no effect while valid is clear. Let it capture on a
    // simultaneous redirect so the MEM trap path does not drive the enable
    // of every IF/ID data bit.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifid_pc <= 32'b0;
            ifid_instr <= 32'h0000_0013;
            ifid_pred_taken <= 1'b0;
            ifid_pred_target <= 32'b0;
            ifid_ifault <= 1'b0;
        end else if (if_adv) begin
            ifid_pc <= pc_r;
            ifid_instr <= if_instr_valid ? if_instr : 32'h0000_0013;
            ifid_pred_taken <= pred_taken_r;
            ifid_pred_target <= pred_target_r;
            ifid_ifault <= if_instr_valid && if_fault;
        end
    end

    // =====================================================================
    // ID stage
    // =====================================================================
    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [31:0] id_imm;
    wire        id_rs1_used, id_rs2_used;
    wire [3:0]  id_alu_op;
    wire [1:0]  id_alu_a_sel, id_alu_b_sel;
    wire [2:0]  id_branch;
    wire [3:0]  id_mem_op;
    wire [1:0]  id_wb_sel;
    wire        id_reg_we;
    wire [1:0]  id_csr_op;
    wire        id_csr_imm;
    wire [11:0] id_csr_addr;
    wire [2:0]  id_sys_op;
    wire [2:0]  id_mul_op;
    wire        id_mul_unsigned;
    wire        id_is_jalr;
    wire        id_illegal;

    rv_decoder #(.ENABLE_M(ENABLE_M)) u_dec (
        .instr(ifid_instr),
        .rs1(id_rs1), .rs2(id_rs2), .rd(id_rd), .imm(id_imm),
        .rs1_used(id_rs1_used), .rs2_used(id_rs2_used),
        .alu_op(id_alu_op), .alu_a_sel(id_alu_a_sel), .alu_b_sel(id_alu_b_sel),
        .branch(id_branch), .mem_op(id_mem_op), .wb_sel(id_wb_sel), .reg_we(id_reg_we),
        .csr_op(id_csr_op), .csr_imm(id_csr_imm), .csr_addr(id_csr_addr),
        .sys_op(id_sys_op), .mul_op(id_mul_op), .mul_unsigned(id_mul_unsigned),
        .is_jalr(id_is_jalr), .illegal(id_illegal)
    );

    // register file
    wire [31:0] rf_rdata1, rf_rdata2;
    wire        wb_reg_we;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;
    rv_regfile #(.STORAGE(REGFILE_STORAGE)) u_rf (
        .clk(clk),
        .raddr1(id_rs1), .rdata1(rf_rdata1),
        .raddr2(id_rs2), .rdata2(rf_rdata2),
        .we(wb_reg_we), .waddr(wb_rd), .wdata(wb_data)
    );

    // ---- ID/EX register ----
    reg         idex_valid;
    reg         idex_ifault;
    reg  [31:0] idex_pc;
    reg  [31:0] idex_instr;     // for mtval on illegal
    reg  [4:0]  idex_rs1, idex_rs2, idex_rd;
    reg  [31:0] idex_rs1_val, idex_rs2_val, idex_imm;
    reg         idex_rs1_used, idex_rs2_used;
    reg  [3:0]  idex_alu_op;
    reg  [1:0]  idex_alu_a_sel, idex_alu_b_sel;
    reg  [2:0]  idex_branch;
    reg  [3:0]  idex_mem_op;
    reg  [1:0]  idex_wb_sel;
    reg         idex_reg_we;
    reg  [1:0]  idex_csr_op;
    reg         idex_csr_imm;
    reg  [11:0] idex_csr_addr;
    reg  [2:0]  idex_sys_op;
    reg  [2:0]  idex_mul_op;
    reg         idex_mul_unsigned;
    reg         idex_is_jalr;
    reg         idex_illegal;
    reg         idex_pred_taken;
    reg  [31:0] idex_pred_target;

    wire idex_is_load = (idex_mem_op >= `MEM_LB) && (idex_mem_op <= `MEM_LHU);

    // load-use hazard: load in EX, consumer in ID
    assign ld_use_stall = idex_valid & idex_is_load & (idex_rd != 5'd0) &
                          ((id_rs1_used & (id_rs1 == idex_rd)) |
                           (id_rs2_used & (id_rs2 == idex_rd))) & ifid_valid;

    // CSR hazard: CSR instruction in ID while an earlier CSR write / mret is
    // still in EX or MEM (they commit in MEM).
    reg exmem_valid, exmem_csr_we, exmem_mret;
    assign csr_stall = ifid_valid & (id_csr_op != `CSR_NONE || id_sys_op == `SYS_MRET) &
                       ((idex_valid & (idex_csr_op != `CSR_NONE || idex_sys_op == `SYS_MRET)) |
                        (exmem_valid & (exmem_csr_we | exmem_mret)));

    assign id_bubble = ~ifid_valid | ld_use_stall | csr_stall | ex_redirect | mem_redirect;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idex_valid <= 1'b0;
            idex_ifault <= 1'b0;
            idex_pc <= 0; idex_instr <= 32'h13;
            idex_rs1 <= 0; idex_rs2 <= 0; idex_rd <= 0;
            idex_rs1_val <= 0; idex_rs2_val <= 0; idex_imm <= 0;
            idex_rs1_used <= 0; idex_rs2_used <= 0;
            idex_alu_op <= 0; idex_alu_a_sel <= 0; idex_alu_b_sel <= 0;
            idex_branch <= 0; idex_mem_op <= 0; idex_wb_sel <= 0; idex_reg_we <= 0;
            idex_csr_op <= 0; idex_csr_imm <= 0; idex_csr_addr <= 0;
            idex_sys_op <= 0; idex_mul_op <= 0; idex_mul_unsigned <= 0;
            idex_is_jalr <= 0; idex_illegal <= 0;
            idex_pred_taken <= 0; idex_pred_target <= 0;
        end else if (id_adv) begin
            idex_valid       <= ~id_bubble;
            idex_ifault      <= ~id_bubble & ifid_ifault;
            idex_pc          <= ifid_pc;
            idex_instr       <= ifid_instr;
            idex_rs1         <= id_rs1;
            idex_rs2         <= id_rs2;
            idex_rd          <= id_rd;
            idex_rs1_val     <= rf_rdata1;
            idex_rs2_val     <= rf_rdata2;
            idex_imm         <= id_imm;
            idex_rs1_used    <= id_rs1_used;
            idex_rs2_used    <= id_rs2_used;
            idex_alu_op      <= id_alu_op;
            idex_alu_a_sel   <= id_alu_a_sel;
            idex_alu_b_sel   <= id_alu_b_sel;
            idex_branch      <= id_bubble ? `BR_NONE  : id_branch;
            idex_mem_op      <= id_bubble ? `MEM_NONE : id_mem_op;
            idex_wb_sel      <= id_wb_sel;
            idex_reg_we      <= id_bubble ? 1'b0 : id_reg_we;
            idex_csr_op      <= id_bubble ? `CSR_NONE : id_csr_op;
            idex_csr_imm     <= id_csr_imm;
            idex_csr_addr    <= id_csr_addr;
            idex_sys_op      <= id_bubble ? `SYS_NONE : id_sys_op;
            idex_mul_op      <= id_bubble ? `MUL_NONE : id_mul_op;
            idex_mul_unsigned<= id_mul_unsigned;
            idex_is_jalr     <= id_is_jalr;
            idex_illegal     <= id_bubble ? 1'b0 : id_illegal;
            idex_pred_taken  <= ifid_pred_taken;
            idex_pred_target <= ifid_pred_target;
        end
    end

    // =====================================================================
    // EX stage
    // =====================================================================
    // forwarding
    reg  [4:0]  exmem_rd;
    reg         exmem_reg_we;
    reg  [31:0] exmem_result;    // ALU / PC4 / CSR result (not load data)
    reg  [1:0]  exmem_wb_sel;
    wire exmem_fwd_ok = exmem_valid & exmem_reg_we & (exmem_wb_sel != `WB_MEM);

    wire [31:0] ex_rs1 = (exmem_fwd_ok && exmem_rd == idex_rs1 && idex_rs1 != 0) ? exmem_result :
                         (wb_reg_we    && wb_rd    == idex_rs1 && idex_rs1 != 0) ? wb_data :
                         idex_rs1_val;
    wire [31:0] ex_rs2 = (exmem_fwd_ok && exmem_rd == idex_rs2 && idex_rs2 != 0) ? exmem_result :
                         (wb_reg_we    && wb_rd    == idex_rs2 && idex_rs2 != 0) ? wb_data :
                         idex_rs2_val;

    wire [31:0] alu_a = (idex_alu_a_sel == `ALUA_PC)   ? idex_pc :
                        (idex_alu_a_sel == `ALUA_ZERO) ? 32'b0   : ex_rs1;
    wire [31:0] alu_b = (idex_alu_b_sel == `ALUB_IMM)  ? idex_imm :
                        (idex_alu_b_sel == `ALUB_FOUR) ? 32'd4    : ex_rs2;
    wire [31:0] alu_y;
    rv_alu u_alu (.op(idex_alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

    wire br_taken_raw;
    rv_branch_cmp u_bcmp (.branch(idex_branch), .a(ex_rs1), .b(ex_rs2), .taken(br_taken_raw));
    wire ex_is_branch = idex_valid & (idex_branch != `BR_NONE);
    wire ex_taken     = ex_is_branch & br_taken_raw;
    // Branch/JAL target from a dedicated adder (pc + imm, no operand muxes):
    // keeps the BTB target compare / redirect off the ALU path. JALR still
    // needs the forwarded rs1, so it uses the ALU result.
    wire [31:0] ex_br_target = idex_pc + idex_imm;
    wire [31:0] ex_jalr_target = ex_rs1 + idex_imm;   // dedicated adder, bypasses ALU op muxes
    wire [31:0] ex_target = idex_is_jalr ? {ex_jalr_target[31:1], 1'b0} : ex_br_target;
    wire [31:0] ex_pc4    = idex_pc + 32'd4;
    // mispredict if actual outcome differs from prediction
    wire [31:0] ex_pred_next = idex_pred_taken ? idex_pred_target : ex_pc4;
    wire [31:0] ex_actual_next = ex_taken ? ex_target : ex_pc4;
    // Mispredict without a 32-bit compare on the common path: outcome bit
    // differs, or both taken but the predicted target is wrong (BTB only).
    // JALR needs forwarded rs1 + imm before the target compare. A taken
    // prediction with the wrong JALR target is corrected in MEM from registered
    // addresses, avoiding this long path into the EX-stage redirect control.
    wire ex_target_wrong = ENABLE_BTB && !idex_is_jalr && (ex_br_target != idex_pred_target);
    assign ex_redirect    = idex_valid & ~pipe_freeze & ~mem_redirect &
                            ((ex_taken ^ idex_pred_taken) | (ex_taken & idex_pred_taken & ex_target_wrong));
    assign ex_redirect_pc = ex_actual_next;

    // CSR read + new value
    wire [31:0] csr_rdata;
    wire        csr_raddr_illegal;
    wire [31:0] csr_src = idex_csr_imm ? idex_imm : ex_rs1;
    wire [31:0] csr_wval = (idex_csr_op == `CSR_RW) ? csr_src :
                           (idex_csr_op == `CSR_RS) ? (csr_rdata | csr_src) :
                                                      (csr_rdata & ~csr_src);
    // CSRRS/CSRRC with rs1=x0 (or zimm=0) do not write
    wire csr_write = (idex_csr_op == `CSR_RW) ||
                     ((idex_csr_op == `CSR_RS || idex_csr_op == `CSR_RC) &&
                      (idex_csr_imm ? (idex_imm != 0) : (idex_rs1 != 0)));
    wire csr_ro_write = csr_write && (idex_csr_addr[11:10] == 2'b11);
    wire ex_csr_illegal = (idex_csr_op != `CSR_NONE) && (csr_raddr_illegal || csr_ro_write);

    // mul/div
    wire        md_done;
    wire [31:0] md_result;
    reg         md_issued;
    reg         md_result_valid;
    reg  [31:0] md_result_hold;
    wire ex_is_muldiv = ENABLE_M && idex_valid && (idex_mul_op != `MUL_NONE);
    wire md_start = ex_is_muldiv & ~md_issued & ~mem_stall;
    generate if (ENABLE_M) begin : g_md
        rv_muldiv u_md (
            .clk(clk), .rst_n(rst_n), .start(md_start),
            .op(idex_mul_op), .op_unsigned(idex_mul_unsigned),
            .a(ex_rs1), .b(ex_rs2), .done(md_done), .result(md_result)
        );
    end else begin : g_nomd
        assign md_done = 1'b0;
        assign md_result = 32'b0;
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            md_issued <= 1'b0;
            md_result_valid <= 1'b0;
            md_result_hold <= 32'b0;
        end else if (ex_adv || !ex_is_muldiv) begin
            md_issued <= 1'b0;
            md_result_valid <= 1'b0;
        end else begin
            if (md_start) md_issued <= 1'b1;
            // MEM may still be waiting for RAM when the one-cycle done pulse
            // arrives. Keep the result until this EX instruction can advance.
            if (md_done) begin
                md_result_valid <= 1'b1;
                md_result_hold <= md_result;
            end
        end
    end
    assign muldiv_stall = ex_is_muldiv & ~(md_done | md_result_valid);

    wire [31:0] ex_result = ex_is_muldiv ? (md_result_valid ? md_result_hold : md_result) :
                            (idex_wb_sel == `WB_PC4) ? ex_pc4 :
                            (idex_wb_sel == `WB_CSR) ? csr_rdata : alu_y;

    // exceptions detected in EX (carried to MEM)
    wire ex_iaddr_misalign = ex_taken & (ex_target[1:0] != 2'b00);
    wire ex_is_load  = idex_is_load;
    wire ex_is_store = (idex_mem_op >= `MEM_SB);
    wire ex_half = (idex_mem_op == `MEM_LH) || (idex_mem_op == `MEM_LHU) || (idex_mem_op == `MEM_SH);
    wire ex_word = (idex_mem_op == `MEM_LW) || (idex_mem_op == `MEM_SW);
    wire ex_maddr_misalign = (ex_is_load | ex_is_store) &
                             ((ex_half & alu_y[0]) | (ex_word & (alu_y[1:0] != 0)));

    // ---- EX/MEM register ----
    reg  [31:0] exmem_pc;
    reg  [31:0] exmem_instr;
    reg  [31:0] exmem_store_data;
    reg  [3:0]  exmem_mem_op;
    reg  [11:0] exmem_csr_addr;
    reg  [31:0] exmem_csr_wval;
    reg  [2:0]  exmem_sys_op;
    reg         exmem_illegal;
    reg         exmem_ifault;
    reg         exmem_jalr_pred_taken;
    reg  [31:0] exmem_pred_target;
    reg         exmem_iaddr_misalign, exmem_maddr_misalign;
    reg  [31:0] exmem_target;
    reg         exmem_is_branch, exmem_mispred, exmem_taken;
    // ... exmem_valid/exmem_csr_we/exmem_mret declared above

    wire ex_bubble = ~idex_valid | mem_redirect;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exmem_valid <= 0; exmem_pc <= 0; exmem_instr <= 32'h13;
            exmem_rd <= 0; exmem_reg_we <= 0; exmem_result <= 0; exmem_wb_sel <= 0;
            exmem_store_data <= 0; exmem_mem_op <= 0;
            exmem_csr_we <= 0; exmem_csr_addr <= 0; exmem_csr_wval <= 0;
            exmem_sys_op <= 0; exmem_mret <= 0; exmem_illegal <= 0;
            exmem_ifault <= 0;
            exmem_jalr_pred_taken <= 0; exmem_pred_target <= 0;
            exmem_iaddr_misalign <= 0; exmem_maddr_misalign <= 0;
            exmem_target <= 0; exmem_is_branch <= 0; exmem_mispred <= 0; exmem_taken <= 0;
        end else if (ex_adv) begin
            exmem_valid      <= ~ex_bubble;
            exmem_pc         <= idex_pc;
            exmem_instr      <= idex_instr;
            exmem_rd         <= idex_rd;
            exmem_reg_we     <= ex_bubble ? 1'b0 : idex_reg_we;
            exmem_result     <= ex_result;
            exmem_wb_sel     <= idex_wb_sel;
            exmem_store_data <= ex_rs2;
            exmem_mem_op     <= ex_bubble ? `MEM_NONE : idex_mem_op;
            exmem_csr_we     <= ex_bubble ? 1'b0 : (csr_write & ~ex_csr_illegal);
            exmem_csr_addr   <= idex_csr_addr;
            exmem_csr_wval   <= csr_wval;
            exmem_sys_op     <= ex_bubble ? `SYS_NONE : idex_sys_op;
            exmem_mret       <= ex_bubble ? 1'b0 : (idex_sys_op == `SYS_MRET);
            exmem_illegal    <= ex_bubble ? 1'b0 : (idex_illegal | ex_csr_illegal);
            exmem_ifault     <= ex_bubble ? 1'b0 : idex_ifault;
            exmem_jalr_pred_taken <= ex_bubble ? 1'b0 : (idex_is_jalr & idex_pred_taken);
            exmem_pred_target <= idex_pred_target;
            exmem_iaddr_misalign <= ex_bubble ? 1'b0 : ex_iaddr_misalign;
            exmem_maddr_misalign <= ex_bubble ? 1'b0 : ex_maddr_misalign;
            exmem_target     <= ex_target;
            exmem_is_branch  <= ex_bubble ? 1'b0 : ex_is_branch;
            exmem_mispred    <= ex_bubble ? 1'b0 : ex_redirect;
            exmem_taken      <= ex_bubble ? 1'b0 : ex_taken;
        end
    end

    // =====================================================================
    // MEM stage
    // =====================================================================
    wire mem_is_load  = (exmem_mem_op >= `MEM_LB) && (exmem_mem_op <= `MEM_LHU);
    wire mem_is_store = (exmem_mem_op >= `MEM_SB);
    wire [1:0] mem_off = exmem_result[1:0];

    // ---- trap decision (before issuing memory request) ----
    wire        irq_pending;
    wire [3:0]  irq_cause;
    wire        mem_access_fault = dmem_fault & (mem_is_load | mem_is_store);
    wire        trap_exc = exmem_valid & (exmem_ifault | exmem_illegal | exmem_iaddr_misalign | exmem_maddr_misalign | mem_access_fault |
                           (exmem_sys_op == `SYS_ECALL) | (exmem_sys_op == `SYS_EBREAK));
    // interrupts are taken on a valid instruction boundary; the instruction in
    // MEM is not executed (mepc = its pc) so it restarts after the handler.
    wire        trap_irq = exmem_valid & irq_pending & ~trap_exc;
    wire        trap_enter = trap_exc | trap_irq;
    reg  [3:0]  trap_cause;
    reg  [31:0] trap_val;
    always @(*) begin
        trap_cause = 4'd0; trap_val = 32'b0;
        if (trap_irq) begin
            trap_cause = irq_cause;
        end else if (exmem_iaddr_misalign) begin
            trap_cause = `EXC_IADDR_MISALIGN; trap_val = exmem_target;
        end else if (exmem_ifault) begin
            trap_cause = `EXC_IACCESS_FAULT; trap_val = exmem_pc;
        end else if (exmem_illegal) begin
            trap_cause = `EXC_ILLEGAL; trap_val = exmem_instr;
        end else if (exmem_sys_op == `SYS_ECALL) begin
            trap_cause = `EXC_ECALL_M;
        end else if (exmem_sys_op == `SYS_EBREAK) begin
            trap_cause = `EXC_BREAKPOINT; trap_val = exmem_pc;
        end else if (exmem_maddr_misalign) begin
            trap_cause = mem_is_store ? `EXC_SADDR_MISALIGN : `EXC_LADDR_MISALIGN;
            trap_val = exmem_result;
        end else if (mem_access_fault) begin
            trap_cause = mem_is_store ? `EXC_SACCESS_FAULT : `EXC_LACCESS_FAULT;
            trap_val = exmem_result;
        end
    end

    wire mem_commit = exmem_valid & ~trap_enter;   // instruction really executes

    // ---- data memory request ----
    // Request is asserted while the instruction sits in MEM; the stage
    // completes when dmem_ready. For a load the data returns on the ready cycle.
    assign dmem_req   = mem_commit & (mem_is_load | mem_is_store);
    assign dmem_we    = mem_is_store;
    assign dmem_addr  = {exmem_result[31:2], 2'b00};
    reg  [3:0]  st_be;
    reg  [31:0] st_data;
    always @(*) begin
        case (exmem_mem_op)
            `MEM_SB: begin st_be = 4'b0001 << mem_off; st_data = {4{exmem_store_data[7:0]}}; end
            `MEM_SH: begin st_be = mem_off[1] ? 4'b1100 : 4'b0011; st_data = {2{exmem_store_data[15:0]}}; end
            default: begin st_be = 4'b1111; st_data = exmem_store_data; end
        endcase
    end
    assign dmem_be    = st_be;
    assign dmem_wdata = st_data;
    assign mem_stall  = dmem_req & ~dmem_ready;

    // load data alignment / extension
    reg [31:0] ld_data;
    wire [7:0]  ld_b = mem_off[1] ? (mem_off[0] ? dmem_rdata[31:24] : dmem_rdata[23:16])
                                  : (mem_off[0] ? dmem_rdata[15:8]  : dmem_rdata[7:0]);
    wire [15:0] ld_h = mem_off[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
    always @(*) begin
        case (exmem_mem_op)
            `MEM_LB:  ld_data = {{24{ld_b[7]}}, ld_b};
            `MEM_LBU: ld_data = {24'b0, ld_b};
            `MEM_LH:  ld_data = {{16{ld_h[15]}}, ld_h};
            `MEM_LHU: ld_data = {16'b0, ld_h};
            default:  ld_data = dmem_rdata;
        endcase
    end

    // ---- CSR file ----
    wire [31:0] trap_vector, mepc_out;
    wire        mem_mret = mem_commit & exmem_mret;
    wire        mem_fencei = mem_commit & (exmem_sys_op == `SYS_FENCEI);
    assign fencei_req = ENABLE_CACHE_FENCE && mem_fencei;
    assign fencei_wait = ENABLE_CACHE_FENCE && mem_fencei && !fencei_done;
    rv_csr #(.ENABLE_M(ENABLE_M)) u_csr (
        .clk(clk), .rst_n(rst_n),
        .raddr(idex_csr_addr), .rdata(csr_rdata), .raddr_illegal(csr_raddr_illegal),
        .we(mem_commit & exmem_csr_we & ~mem_stall), .waddr(exmem_csr_addr), .wdata(exmem_csr_wval),
        .trap_enter(trap_enter & ~pipe_freeze), .trap_is_irq(trap_irq), .trap_cause(trap_cause),
        .trap_pc(exmem_pc), .trap_val(trap_val),
        .mret(mem_mret & ~pipe_freeze),
        .trap_vector(trap_vector), .mepc_out(mepc_out),
        .irq_software(irq_software), .irq_timer(irq_timer), .irq_external(irq_external),
        .irq_pending(irq_pending), .irq_cause(irq_cause),
        .instr_retired(ev_instr_retired)
    );

    // A dynamic JALR may reuse a BTB entry but change its target. Correct it
    // one stage later so the 32-bit target add and compare are in different
    // cycles. MEM has priority over redirects from younger EX instructions.
    wire mem_jalr_target_miss = ENABLE_BTB && exmem_valid && exmem_jalr_pred_taken &&
                                (exmem_target != exmem_pred_target);
    // MEM-stage redirect: trap, mret, fence.i, or late JALR correction.
    assign mem_redirect = ~pipe_freeze & (trap_enter | mem_mret | mem_fencei | mem_jalr_target_miss);
    assign mem_redirect_pc = trap_enter ? trap_vector :
                             mem_mret   ? mepc_out    :
                             mem_jalr_target_miss ? exmem_target :
                             (exmem_pc + 32'd4);

    // ---- MEM/WB register ----
    reg         memwb_reg_we;
    reg  [4:0]  memwb_rd;
    reg  [31:0] memwb_data;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memwb_reg_we <= 1'b0; memwb_rd <= 5'd0; memwb_data <= 32'b0;
        end else if (mem_adv) begin
            memwb_reg_we <= mem_commit & exmem_reg_we;
            memwb_rd     <= exmem_rd;
            memwb_data   <= mem_is_load ? ld_data : exmem_result;
        end
    end

    // =====================================================================
    // WB stage
    // =====================================================================
    assign wb_reg_we = memwb_reg_we;
    assign wb_rd     = memwb_rd;
    assign wb_data   = memwb_data;

    // =====================================================================
    // BTB (stage 2) - stub when disabled
    // =====================================================================
    // A branch in MEM cannot itself assert mem_stall or fencei_wait. Only an
    // in-flight younger multiply/divide can freeze it. Avoid routing the
    // unrelated data-address/access-fault logic through the BTB write enable.
    wire branch_adv = ~muldiv_stall;
    generate if (ENABLE_BTB) begin : g_btb
        rv_btb #(.ENTRIES(BTB_ENTRIES)) u_btb (
            .clk(clk), .rst_n(rst_n),
            .lookup_pc(pc), .hit(btb_hit), .target(btb_target),
            .update(exmem_valid & exmem_is_branch & branch_adv),
            .update_pc(exmem_pc), .update_taken(exmem_taken), .update_target(exmem_target)
        );
    end else begin : g_nobtb
        assign btb_hit = 1'b0;
        assign btb_target = 32'b0;
    end endgenerate

    // =====================================================================
    // performance events
    // =====================================================================
    assign ev_instr_retired  = mem_commit & mem_adv & ~mem_stall;
    assign ev_branch         = exmem_valid & exmem_is_branch & branch_adv;
    assign ev_branch_mispred = exmem_valid & (exmem_mispred | mem_jalr_target_miss) & branch_adv;
    assign ev_load_use_stall = ld_use_stall & ~pipe_freeze;
    assign ev_imem_stall     = if_stall & ~pipe_freeze;
    assign ev_dmem_stall     = mem_stall;
    assign ev_trap           = trap_enter & ~pipe_freeze;

    // Optional diagnostic bank, absent in ordinary builds. FIC retains this
    // observer in a diagnostic build; all flags and the PC have the same
    // one-cycle delay. It has no path back to functional state or outputs.
    // Keep the register at a fixed hierarchy: ADS/FIC normalizes dots in
    // generated instance names differently from the synthesized netlist.
    // Ordinary builds do not retain this constant-zero bank.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pipeline_probe_q <= 26'b0;
        else if (ENABLE_PIPELINE_PROBE)
            pipeline_probe_q <= {trap_enter, mem_stall, muldiv_stall,
                ld_use_stall, if_stall, pipe_freeze, mem_commit, exmem_valid,
                idex_valid, ifid_valid, if_valid,
                (exmem_pc[31:16] == 16'b0), exmem_pc[15:2]};
        else pipeline_probe_q <= 26'b0;
    end

endmodule
