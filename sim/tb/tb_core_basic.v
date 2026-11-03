// tb_core_basic.v - smoke test for rv_core with an ideal 1-cycle memory.
// Loads a hex program (word per line) into a unified RAM and runs until the
// program writes to TOHOST_ADDR (riscv-tests convention: 1 = pass, else fail)
// or a timeout expires. A store to UART_ADDR prints a character.
`timescale 1ns/1ps
module tb_core_basic;
    parameter MEM_WORDS   = 16384;              // 64 KB
    parameter TOHOST_ADDR = 32'h0000_F000;      // matches sim/riscv-tests/link.ld (.tohost)
    parameter UART_ADDR   = 32'h4000_0000;
    parameter TIMEOUT     = 200_000;
    parameter ENABLE_M    = 1;
    parameter ENABLE_BTB  = 0;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;   // 100 MHz

    wire        imem_req, dmem_req, dmem_we;
    wire [31:0] imem_addr, dmem_addr, dmem_wdata;
    wire [3:0]  dmem_be;
    reg  [31:0] imem_rdata, dmem_rdata;
    wire        ev_ret, ev_br, ev_mp, ev_lu, ev_is, ev_ds, ev_tr;

    rv_core #(.RESET_PC(32'h0000_0000), .ENABLE_M(ENABLE_M), .ENABLE_BTB(ENABLE_BTB)) dut (
        .clk(clk), .rst_n(rst_n),
        .imem_req(imem_req), .imem_addr(imem_addr), .imem_rdata(imem_rdata), .imem_ready(1'b1), .imem_fault(1'b0),
        .dmem_req(dmem_req), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata), .dmem_ready(1'b1), .dmem_fault(1'b0),
        .irq_software(1'b0), .irq_timer(1'b0), .irq_external(1'b0),
        .ev_instr_retired(ev_ret), .ev_branch(ev_br), .ev_branch_mispred(ev_mp),
        .ev_load_use_stall(ev_lu), .ev_imem_stall(ev_is), .ev_dmem_stall(ev_ds), .ev_trap(ev_tr)
    );

    // unified memory. Instruction port: synchronous read (data next cycle),
    // matching the core's fetch protocol. Data port: combinational read so
    // the MEM stage sees data in the same cycle it asserts dmem_req with
    // dmem_ready=1 (a DRM-based memory will instead delay dmem_ready).
    reg [31:0] mem [0:MEM_WORDS-1];
    wire [$clog2(MEM_WORDS)-1:0] ia = imem_addr[$clog2(MEM_WORDS)+1:2];
    wire [$clog2(MEM_WORDS)-1:0] da = dmem_addr[$clog2(MEM_WORDS)+1:2];
    always @(posedge clk) begin
        imem_rdata <= (imem_addr < MEM_WORDS*4) ? mem[ia] : 32'h0;
        if (dmem_req && dmem_we && dmem_addr < (MEM_WORDS*4)) begin
            if (dmem_be[0]) mem[da][7:0]   <= dmem_wdata[7:0];
            if (dmem_be[1]) mem[da][15:8]  <= dmem_wdata[15:8];
            if (dmem_be[2]) mem[da][23:16] <= dmem_wdata[23:16];
            if (dmem_be[3]) mem[da][31:24] <= dmem_wdata[31:24];
        end
    end
    always @(*) dmem_rdata = (dmem_addr < MEM_WORDS*4) ? mem[da] : 32'hDEAD_BEEF;

    // counters
    integer cyc = 0, ret = 0, br = 0, mp = 0, lu = 0;
    reg trace = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (ev_ret) ret <= ret + 1;
        if (ev_br)  br  <= br  + 1;
        if (ev_mp)  mp  <= mp  + 1;
        if (ev_lu)  lu  <= lu  + 1;
        if (trace && ev_ret)
            $display("%6d pc=%08x instr=%08x rd=x%0d we=%b res=%08x dreq=%b we=%b addr=%08x",
                     cyc, dut.exmem_pc, dut.exmem_instr, dut.exmem_rd, dut.exmem_reg_we,
                     dut.exmem_result, dmem_req, dmem_we, dmem_addr);
    end

    // tohost / uart
    reg [1023:0] hexfile;
    integer status = -1;
    always @(posedge clk) begin
        if (dmem_req && dmem_we) begin
            if (dmem_addr == UART_ADDR) $write("%c", dmem_wdata[7:0]);
            if (dmem_addr == TOHOST_ADDR) begin
                status = dmem_wdata;
                #1;
                if (status == 1) $display("\n[PASS] cycles=%0d instrs=%0d CPI=%.3f branches=%0d mispred=%0d ld_use=%0d",
                                          cyc, ret, cyc*1.0/ret, br, mp, lu);
                else             $display("\n[FAIL] tohost=0x%08x (test #%0d) pc=0x%08x", status, status>>1, dut.exmem_pc);
                $finish;
            end
        end
    end

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 32'h0000_0013;
        if (!$value$plusargs("hex=%s", hexfile)) hexfile = "prog.hex";
        $readmemh(hexfile, mem);
        if ($test$plusargs("trace")) trace = 1;
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_core_basic.vcd");
            $dumpvars(0, tb_core_basic);
        end
        #23 rst_n = 1;
        #(TIMEOUT*10);
        $display("\n[TIMEOUT] pc=0x%08x", dut.pc);
        $finish;
    end
endmodule
