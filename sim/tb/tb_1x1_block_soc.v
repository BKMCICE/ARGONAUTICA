`timescale 1ns/1ps
module tb_1x1_block_soc #(parameter ENABLE_BLOCK=1);
    tb_soc_ddr #(.ENABLE_AI_BLOCK(ENABLE_BLOCK)) base();
    reg [31:0] result_addr;
    integer block_starts=0,legacy_starts=0,word_writes=0,raw_reads=0;
    initial if(!$value$plusargs("block_tohost=%h",result_addr)) $fatal(1,"block_tohost required");
    always @(posedge base.clk) if(base.rst_n && base.dut.u_core.dmem_req && base.dut.u_core.dmem_ready) begin
        if(base.dut.u_core.dmem_we) begin
            case(base.dut.u_core.dmem_addr)
                32'h40004104:if(base.dut.u_core.dmem_wdata[0]) block_starts=block_starts+1;
                32'h40004000:if(base.dut.u_core.dmem_wdata[0]) legacy_starts=legacy_starts+1;
                32'h40004110,32'h40004118:word_writes=word_writes+1;
                default:;
            endcase
            if(base.dut.u_core.dmem_addr==result_addr && base.dut.u_core.dmem_wdata!=0) begin
                if(ENABLE_BLOCK) begin
                    if(base.dut.u_core.dmem_wdata!==1 || block_starts!=49 || legacy_starts!=800 || word_writes!=6300 || raw_reads!=560)
                        $fatal(1,"A01 SoC fail exit=%h block=%0d legacy=%0d",base.dut.u_core.dmem_wdata,block_starts,legacy_starts);
                    $display("A01_COMPLETE_SOC_PASS blocks=%0d legacy_dots=%0d buffer_words=%0d result_reads=%0d",block_starts,legacy_starts,word_writes,raw_reads);
                end else begin
                    if(base.dut.u_core.dmem_wdata!==2 || block_starts!=0 || legacy_starts!=0 || word_writes!=0 || raw_reads!=0)
                        $fatal(1,"Disabled block driver was not safely rejected");
                    $display("A02_DISABLED_TOP_SAFE_UNSUPPORTED_PASS");
                end
                $finish;
            end
        end else if(base.dut.u_core.dmem_addr==32'h40004120) raw_reads=raw_reads+1;
    end
endmodule
