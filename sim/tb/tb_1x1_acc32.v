`timescale 1ns/1ps
// Production batch-8 convolution through CPU/cache/DDR/TCM and real AI MMIO.
module tb_1x1_acc32;
    tb_soc_ddr base();
    reg [31:0] result_addr;
    integer starts=0, weight_writes=0, pixel_writes=0;
    initial if (!$value$plusargs("stack_tohost=%h",result_addr)) $fatal(1,"stack_tohost required");
    always @(posedge base.clk) begin
        if(base.rst_n && base.dut.u_core.dmem_req && base.dut.u_core.dmem_ready && base.dut.u_core.dmem_we) begin
            case(base.dut.u_core.dmem_addr)
                32'h40004000: if(base.dut.u_core.dmem_wdata[0]) starts=starts+1;
                32'h40004004,32'h40004008,32'h4000400c: pixel_writes=pixel_writes+1;
                32'h40004010,32'h40004014,32'h40004018: weight_writes=weight_writes+1;
            endcase
            if(base.dut.u_core.dmem_addr==result_addr) begin
                if(base.dut.u_core.dmem_wdata!==32'd1) $fatal(1,"Operator self-test failed: %h",base.dut.u_core.dmem_wdata);
                if(starts!=31614 || weight_writes!=25668 || pixel_writes!=94842)
                    $fatal(1,"Unexpected AI traffic: starts=%0d weights=%0d pixels=%0d",starts,weight_writes,pixel_writes);
                $display("\nACC32_MMIO_RTL_PASS starts=%0d weight_writes=%0d pixel_writes=%0d",starts,weight_writes,pixel_writes);
                $finish;
            end
        end
    end
endmodule
