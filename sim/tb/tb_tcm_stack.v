`timescale 1ns/1ps
// Small complete startup check: DDR image -> TCM copy -> local stack/data ports.
// The original DDR harness supplies the real caches/bridge/DDR model and UART.
module tb_tcm_stack;
    tb_soc_ddr base();
    reg [31:0] result_addr;
    reg expect_guard_corruption;
    initial begin
        if (!$value$plusargs("stack_tohost=%h",result_addr)) $fatal(1,"stack_tohost required");
        expect_guard_corruption=$test$plusargs("expect_guard_corruption");
    end
    always @(posedge base.clk) begin
        if (base.rst_n && base.dut.u_core.dmem_req && base.dut.u_core.dmem_ready &&
            base.dut.u_core.dmem_we && base.dut.u_core.dmem_addr==result_addr) begin
            if (base.dut.u_core.dmem_wdata !== (expect_guard_corruption ? 32'd9 : 32'd1))
                $fatal(1,"Unexpected stack self-test exit %h",base.dut.u_core.dmem_wdata);
            $display("\nTCM_STACK_RTL_PASS expected_guard_corruption=%0d",expect_guard_corruption);
            $finish;
        end
    end
endmodule
