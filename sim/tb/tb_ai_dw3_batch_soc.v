`timescale 1ns/1ps
module tb_ai_dw3_batch_soc;
    tb_soc_ddr #(.ENABLE_AI_BLOCK(1),.ENABLE_AI_QUANT(1),.ENABLE_AI_BLOCK8(1),
        .ICACHE_DRM(1),.DCACHE_TAG_STORAGE(2),.REGFILE_STORAGE(1),.DDR_LINE_ADDR_BITS(16)) base();
    reg [31:0] result_addr,crt_addr,phase_addr;
    integer phase=0,i,j,n,seen=0,index;
    integer reads[1:2][0:255],writes[1:2][0:255];
    integer tasks[1:2],dots[1:2],items[1:2],raw_starts[1:2];
    initial begin
        if(base.dut.ICACHE_DRM!=1 || base.dut.DCACHE_TAG_STORAGE!=2 || base.dut.REGFILE_STORAGE!=1)$fatal(1,"storage mismatch");
        if(!$value$plusargs("block_tohost=%h",result_addr)||!$value$plusargs("crt_tohost=%h",crt_addr)||!$value$plusargs("phase_addr=%h",phase_addr))$fatal(1,"missing symbols");
        for(i=1;i<=2;i=i+1)begin tasks[i]=0;dots[i]=0;items[i]=0;raw_starts[i]=0;
            for(j=0;j<256;j=j+1)begin reads[i][j]=0;writes[i][j]=0;end
        end
    end
    generate if(`A53_ON)begin
        always @(posedge base.clk)if(base.rst_n&&phase!=0)begin
            if(base.dut.u_ai.new_engine.batch.state==1)dots[phase]=dots[phase]+1;
            if(base.dut.u_ai.new_engine.batch.state==4&&base.dut.u_ai.new_engine.batch.qdone&&!base.dut.u_ai.new_engine.batch.qerror)items[phase]=items[phase]+1;
            if(base.dut.u_ai.new_engine.batch.req&&base.dut.u_ai.new_engine.batch.we&&base.dut.u_ai.new_engine.batch.addr[11:0]=='h304&&base.dut.u_ai.new_engine.batch.wdata==1&&!base.dut.u_ai.new_engine.batch.busy)tasks[phase]=tasks[phase]+1;
        end
    end endgenerate
    always @(posedge base.clk)if(base.rst_n)begin
        if((base.awvalid&&base.awready&&base.awaddr>=28'd524288)||(base.arvalid&&base.arready&&base.araddr>=28'd524288))$fatal(1,"DDR outside 2MiB");
        if(base.dut.u_core.pc==32'h8000)$fatal(1,"unexpected trap");
        if(base.dut.u_core.dmem_req&&base.dut.u_core.dmem_ready)begin
            if(base.dut.u_core.dmem_we)begin
                if(base.dut.u_core.dmem_addr==phase_addr)begin phase=base.dut.u_core.dmem_wdata;if(phase>2)$fatal(1,"bad phase");end
                if(base.dut.u_core.dmem_addr==result_addr&&base.dut.u_core.dmem_wdata!=0)begin
                    if(base.dut.u_core.dmem_wdata!=1)$fatal(1,"bad result");seen=1;
                end
                if(base.dut.u_core.dmem_addr==crt_addr&&base.dut.u_core.dmem_wdata!=0)begin
                    if(!seen||base.dut.u_core.dmem_wdata!=1)$fatal(1,"main/guard failed");
                    for(n=1;n<=2;n=n+1)begin
                        for(j=0;j<256;j=j+1)begin
                            if(reads[n][j])$display("A53_MMIO phase=%0d read offset=%03x count=%0d",n,j*4,reads[n][j]);
                            if(writes[n][j])$display("A53_MMIO phase=%0d write offset=%03x count=%0d",n,j*4,writes[n][j]);
                        end
                        $display("A53_ENGINE phase=%0d tasks=%0d dots=%0d items=%0d raw_starts=%0d",n,tasks[n],dots[n],items[n],raw_starts[n]);
                    end
                    $display("A53_RV32_DDR_PASS enabled=%0d",`A53_ON);$finish;
                end
            end
            if(phase!=0&&base.dut.u_core.dmem_addr>=32'h40004000&&base.dut.u_core.dmem_addr<32'h40005000)begin
                if(base.dut.u_core.dmem_addr[11:0]>='h340||base.dut.u_core.dmem_addr[1:0]!=0)$fatal(1,"unexpected offset");
                index=base.dut.u_core.dmem_addr[9:2];
                if(base.dut.u_core.dmem_we)begin
                    writes[phase][index]=writes[phase][index]+1;
                    if(index==0&&base.dut.u_core.dmem_wdata[0])raw_starts[phase]=raw_starts[phase]+1;
                end else reads[phase][index]=reads[phase][index]+1;
            end
        end
    end
endmodule
