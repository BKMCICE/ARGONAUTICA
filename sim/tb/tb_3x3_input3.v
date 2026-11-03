`timescale 1ns/1ps
// Real CPU/cache/DDR/TCM and AI unit, including MMIO submission ordering.
module tb_3x3_input3;
    tb_soc_ddr base();
    reg [31:0] result_addr;
    integer starts=0, weight_writes=0, pixel_writes=0, acc_reads=0;
    reg [2:0] weights=0, pixels=0;
    reg active=0, done_seen=0;
    initial if (!$value$plusargs("stack_tohost=%h",result_addr)) $fatal(1,"stack_tohost required");
    always @(posedge base.clk) begin
        if(base.rst_n && base.dut.u_core.dmem_req && base.dut.u_core.dmem_ready) begin
            if(base.dut.u_core.dmem_we) begin
                case(base.dut.u_core.dmem_addr)
                    32'h40004004,32'h40004008,32'h4000400c: begin
                        if(active) $fatal(1,"PIX changed before prior ACC read");
                        pixels[(base.dut.u_core.dmem_addr-32'h40004004)>>2]=1;
                        pixel_writes=pixel_writes+1;
                        if(base.dut.u_core.dmem_addr==32'h4000400c && base.dut.u_core.dmem_wdata[31:8]!=0)
                            $fatal(1,"Unused PIX2 bytes not zero");
                    end
                    32'h40004010,32'h40004014,32'h40004018: begin
                        if(active) $fatal(1,"WGT changed before prior ACC read");
                        weights[(base.dut.u_core.dmem_addr-32'h40004010)>>2]=1;
                        weight_writes=weight_writes+1;
                        if(base.dut.u_core.dmem_addr==32'h40004018 && base.dut.u_core.dmem_wdata[31:8]!=0)
                            $fatal(1,"Unused WGT2 bytes not zero");
                    end
                    32'h4000401c: if(base.dut.u_core.dmem_wdata!=0) $fatal(1,"Nonzero AI bias");
                    32'h40004000: if(base.dut.u_core.dmem_wdata[0]) begin
                        if(active || weights!=7 || pixels!=7) $fatal(1,"Incomplete or overlapping AI start");
                        starts=starts+1;active=1;done_seen=0;weights=0;pixels=0;
                    end
                endcase
                if(base.dut.u_core.dmem_addr==result_addr) begin
                    if(base.dut.u_core.dmem_wdata!==32'd1) $fatal(1,"Scalar self-test failed: %h",base.dut.u_core.dmem_wdata);
                    if(active || weights!=0 || pixels!=0 || starts!=7326 || acc_reads!=7326 || weight_writes!=21978 || pixel_writes!=21978)
                        $fatal(1,"Unexpected AI traffic: starts=%0d acc=%0d weights=%0d pixels=%0d",starts,acc_reads,weight_writes,pixel_writes);
                    $display("\nINPUT3_MMIO_RTL_PASS starts=%0d acc_reads=%0d weight_writes=%0d pixel_writes=%0d ordering=PASS",starts,acc_reads,weight_writes,pixel_writes);
                    $finish;
                end
            end else begin
                if(base.dut.u_core.dmem_addr==32'h40004000 && active && base.dut.u_core.dmem_rdata[1]) done_seen=1;
                if(base.dut.u_core.dmem_addr==32'h40004024) begin
                    if(!active || !done_seen) $fatal(1,"ACC read without completed AI start");
                    acc_reads=acc_reads+1;active=0;
                end
            end
        end
    end
endmodule
