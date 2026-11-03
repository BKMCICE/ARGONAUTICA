// tb_soc.v - simulate soc_top with a UART monitor. Program is loaded via
// +hex=<file> into the SoC RAM. Ends when the program writes tohost
// (0xF000) or on timeout. +vcd dumps waves.
`timescale 1ns/1ps
module tb_soc;
    parameter CLK_HZ  = 100_000_000;
    parameter BAUD    = 115200;         // fast baud in sim keeps runtime low
    parameter ENABLE_BTB = 0;
    parameter TIMEOUT_CYCLES = 50_000_000;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire       txd;
    wire [7:0] leds;
    reg  [7:0] gpio_keys = 8'hFF;
    reg  [1023:0] hexfile;

    soc_top #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .RAM_ADDR_W(14), .ENABLE_M(1), .ENABLE_BTB(ENABLE_BTB)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rxd(1'b1), .uart_txd(txd),
        .gpio_out(leds), .gpio_in(gpio_keys)
    );

    // An optional simulated key press exercises the GPIO -> external IRQ path.
    initial if ($test$plusargs("gpio_irq")) begin
        wait (rst_n && dut.u_gpio.irq_en[0]);
        repeat (20) @(posedge clk);
        gpio_keys[0] = 1'b0;
    end

    // ---- UART monitor (8N1) ----
    localparam integer BIT_CYC = CLK_HZ / BAUD;
    integer bitcnt; reg [7:0] sh;
    initial begin
        forever begin
            @(negedge txd);
            #(BIT_CYC * 10 / 2);            // middle of start bit (10 ns per cycle)
            for (bitcnt = 0; bitcnt < 8; bitcnt = bitcnt + 1) begin
                #(BIT_CYC * 10);
                sh[bitcnt] = txd;
            end
            #(BIT_CYC * 10);
            $write("%c", sh);
            $fflush();
        end
    end

    // ---- tohost watch ----
    integer cyc = 0;
    integer jalr_late_count = 0;
    integer timeout_cycles = TIMEOUT_CYCLES;
    integer drain_cycles;
    integer progress_interval = 0;
    integer trace_from = 0;
    integer trace_to = 2147483647;
    reg [31:0] exit_status;
    reg trace = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (dut.u_core.mem_jalr_target_miss && !dut.u_core.pipe_freeze)
            jalr_late_count <= jalr_late_count + 1;
        if (trace && cyc >= trace_from && cyc <= trace_to && dut.u_core.ev_instr_retired)
            $display("%8d pc=%08x i=%08x rd=x%0d res=%08x", cyc, dut.u_core.exmem_pc,
                     dut.u_core.exmem_instr, dut.u_core.exmem_rd, dut.u_core.exmem_result);
        if (progress_interval > 0 && cyc > 0 && cyc % progress_interval == 0)
            $display("[PROGRESS] cycles=%0d pc=0x%08x instret=%0d idex=0x%08x md={start:%b issued:%b done:%b busy:%b cnt:%0d} stall={mem:%b muldiv:%b}",
                     cyc, dut.u_core.pc, dut.u_core.u_csr.minstret[31:0],
                     dut.u_core.idex_pc, dut.u_core.md_start, dut.u_core.md_issued,
                     dut.u_core.md_done, dut.u_core.g_md.u_md.div_busy,
                     dut.u_core.g_md.u_md.div_cnt, dut.u_core.mem_stall,
                     dut.u_core.muldiv_stall);
        if (dut.u_ram.d_req && dut.u_ram.d_we && dut.u_ram.d_addr == 32'h0000_F000 && !dut.u_ram.d_pending) begin
            exit_status = dut.u_ram.d_wdata;
            #1;
            for (drain_cycles = 0; drain_cycles < BIT_CYC * 10 * 20 &&
                 (!dut.u_uart.tx_empty || dut.u_uart.tx_bit != 0); drain_cycles = drain_cycles + 1)
                @(posedge clk);
            #(BIT_CYC * 10);                // finish UART monitor's last stop bit
            if ($test$plusargs("require_jalr_late"))
                $display("[JALR_LATE] corrections=%0d", jalr_late_count);
            if (drain_cycles == BIT_CYC * 10 * 20)
                $display("\n[ERROR] UART did not drain after tohost write");
            else if ($test$plusargs("require_jalr_late") && jalr_late_count == 0)
                $fatal(1, "late JALR target correction was not exercised");
            else if (exit_status == 32'h1)
                $display("\n[EXIT] tohost=0x%08x cycles=%0d", exit_status, cyc);
            else
                $display("\n[FAIL] tohost=0x%08x cycles=%0d", exit_status, cyc);
            $finish;
        end
        if (cyc == timeout_cycles) begin
            $display("\n[TIMEOUT] pc=0x%08x", dut.u_core.pc);
            $finish;
        end
    end

    initial begin
        if (!$value$plusargs("hex=%s", hexfile)) hexfile = "prog.hex";
        if (!$value$plusargs("timeout=%d", timeout_cycles)) timeout_cycles = TIMEOUT_CYCLES;
        if (!$value$plusargs("progress=%d", progress_interval)) progress_interval = 0;
        if ($value$plusargs("trace_from=%d", trace_from)) trace = 1;
        if ($value$plusargs("trace_to=%d", trace_to)) trace = 1;
        $readmemh(hexfile, dut.u_ram.mem);
        if ($test$plusargs("trace")) trace = 1;
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_soc.vcd");
            $dumpvars(0, tb_soc);
        end
        #33 rst_n = 1;
    end
endmodule
