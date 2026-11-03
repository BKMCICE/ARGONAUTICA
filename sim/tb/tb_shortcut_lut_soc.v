`timescale 1ns/1ps
module tb_shortcut_lut_soc;
    tb_soc_ddr #(.ENABLE_BTB(1),.ENABLE_AI_BLOCK(1),.ENABLE_AI_QUANT(1),.ENABLE_AI_BLOCK8(1),
        .ICACHE_DRM(1),.ICACHE_EARLY_READ(1),.DCACHE_TAG_STORAGE(2),.REGFILE_STORAGE(1),
        .DDR_LINE_ADDR_BITS(16)) base();
    reg [31:0] result_addr,crt_addr;
    reg seen=0;
    initial begin
        if(!$value$plusargs("result_addr=%h",result_addr)||!$value$plusargs("crt_addr=%h",crt_addr))$fatal(1,"missing ELF symbols");
    end
    always @(posedge base.clk) if(base.rst_n) begin
        if((base.awvalid&&base.awready&&base.awaddr>=28'd524288)||(base.arvalid&&base.arready&&base.araddr>=28'd524288))$fatal(1,"DDR outside 2MiB fixture");
        if(base.dut.u_core.pc==32'h8000)$fatal(1,"unexpected trap");
        if(base.dut.u_core.dmem_req&&base.dut.u_core.dmem_ready)begin
            if(base.dut.u_core.dmem_addr>=32'h40004000&&base.dut.u_core.dmem_addr<32'h40005000)$fatal(1,"unexpected AI MMIO");
            if(base.dut.u_core.dmem_we&&base.dut.u_core.dmem_addr==result_addr&&base.dut.u_core.dmem_wdata!=0)begin
                if(base.dut.u_core.dmem_wdata!=1)$fatal(1,"diagnostic failed");seen=1;
            end
            if(base.dut.u_core.dmem_we&&base.dut.u_core.dmem_addr==crt_addr&&base.dut.u_core.dmem_wdata!=0)begin
                if(!seen||base.dut.u_core.dmem_wdata!=1)$fatal(1,"return/stack guard failed");
                $display("A65_RV32_DDR_PASS cycles=%0d",base.cycles);$finish;
            end
        end
    end
endmodule
