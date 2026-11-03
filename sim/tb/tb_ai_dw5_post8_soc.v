`timescale 1ns/1ps
module tb_ai_dw5_post8_soc #(parameter QUANT_ENABLE=1, parameter BLOCK8_ENABLE=1);
    tb_soc_ddr #(.ENABLE_AI_BLOCK(1),.ENABLE_AI_QUANT(QUANT_ENABLE),.ENABLE_AI_BLOCK8(BLOCK8_ENABLE),
        .ICACHE_DRM(1),.DCACHE_TAG_STORAGE(2),.REGFILE_STORAGE(1),.DDR_LINE_ADDR_BITS(16)) base();
    reg [31:0] result_addr,crt_addr,phase_addr;
    integer phase=0,i,j,n,seen=0,index;
    integer reads[1:2][0:255],writes[1:2][0:255];
    integer tasks[1:2],dots[1:2],core_cycles[1:2],post_items[1:2],post_cycles[1:2],owner_cycles[1:2];
    initial begin
        if(base.dut.ICACHE_DRM!=1 || base.dut.DCACHE_TAG_STORAGE!=2 || base.dut.REGFILE_STORAGE!=1)$fatal(1,"Storage profile mismatch");
        $display("A54_STORAGE_PROFILE icache_drm=1 dcache_tag_storage=2 regfile_storage=1");
        if(!$value$plusargs("block_tohost=%h",result_addr)||!$value$plusargs("crt_tohost=%h",crt_addr)||
           !$value$plusargs("phase_addr=%h",phase_addr))$fatal(1,"Missing symbols");
        for(i=1;i<=2;i=i+1)begin
            tasks[i]=0;dots[i]=0;core_cycles[i]=0;post_items[i]=0;post_cycles[i]=0;owner_cycles[i]=0;
            for(j=0;j<256;j=j+1)begin reads[i][j]=0;writes[i][j]=0;end
        end
    end
    generate if(QUANT_ENABLE)begin
        always @(posedge base.clk)if(base.rst_n && phase!=0)begin
            if(base.dut.u_ai.block8_quant_engine.u_impl.core_req && base.dut.u_ai.block8_quant_engine.u_impl.core_we &&
               base.dut.u_ai.block8_quant_engine.u_impl.core_addr[11:0]=='h104 && base.dut.u_ai.block8_quant_engine.u_impl.core_wdata[0] &&
               !base.dut.u_ai.block8_quant_engine.u_impl.core_busy)tasks[phase]=tasks[phase]+1;
            if(base.dut.u_ai.block8_quant_engine.u_impl.core.tile_state==2)dots[phase]=dots[phase]+1;
            if(base.dut.u_ai.block8_quant_engine.u_impl.core_busy)core_cycles[phase]=core_cycles[phase]+1;
            if(base.dut.u_ai.block8_quant_engine.u_impl.state==5)post_items[phase]=post_items[phase]+1;
            if(base.dut.u_ai.block8_quant_engine.u_impl.quant_busy)post_cycles[phase]=post_cycles[phase]+1;
            if(base.dut.u_ai.block8_quant_engine.u_impl.state!=0)owner_cycles[phase]=owner_cycles[phase]+1;
        end
    end else if(BLOCK8_ENABLE)begin
        always @(posedge base.clk)if(base.rst_n && phase!=0)begin
            if(base.dut.u_ai.block8_engine.u_impl.req && base.dut.u_ai.block8_engine.u_impl.we &&
               base.dut.u_ai.block8_engine.u_impl.addr[11:0]=='h104 && base.dut.u_ai.block8_engine.u_impl.wdata[0] &&
               !base.dut.u_ai.block8_engine.u_impl.busy)tasks[phase]=tasks[phase]+1;
            if(base.dut.u_ai.block8_engine.u_impl.tile_state==2)dots[phase]=dots[phase]+1;
            if(base.dut.u_ai.block8_engine.u_impl.busy)core_cycles[phase]=core_cycles[phase]+1;
        end
    end else begin
        always @(posedge base.clk)if(base.rst_n && phase!=0)begin
            if(base.dut.u_ai.block_engine.u_impl.req && base.dut.u_ai.block_engine.u_impl.we &&
               base.dut.u_ai.block_engine.u_impl.addr[11:0]=='h104 && base.dut.u_ai.block_engine.u_impl.wdata[0] &&
               !base.dut.u_ai.block_engine.u_impl.busy)tasks[phase]=tasks[phase]+1;
            if(base.dut.u_ai.block_engine.u_impl.tile_state==2)dots[phase]=dots[phase]+1;
            if(base.dut.u_ai.block_engine.u_impl.busy)core_cycles[phase]=core_cycles[phase]+1;
        end
    end endgenerate
    always @(posedge base.clk)if(base.rst_n)begin
        if((base.awvalid&&base.awready&&base.awaddr>=28'd524288)||
           (base.arvalid&&base.arready&&base.araddr>=28'd524288))$fatal(1,"DDR outside 2MiB model");
        if(base.dut.u_core.pc==32'h8000)$fatal(1,"Unexpected trap");
        if(base.dut.u_core.dmem_req && base.dut.u_core.dmem_ready)begin
            if(base.dut.u_core.dmem_we)begin
                if(base.dut.u_core.dmem_addr==phase_addr)begin phase=base.dut.u_core.dmem_wdata;if(phase>2)$fatal(1,"bad phase");end
                if(base.dut.u_core.dmem_addr==result_addr && base.dut.u_core.dmem_wdata!=0)begin
                    if(base.dut.u_core.dmem_wdata!=1)$fatal(1,"bad result");seen=1;
                end
                if(base.dut.u_core.dmem_addr==crt_addr && base.dut.u_core.dmem_wdata!=0)begin
                    if(!seen||base.dut.u_core.dmem_wdata!=1)$fatal(1,"main/guard failed");
                    for(n=1;n<=2;n=n+1)begin
                        for(j=0;j<256;j=j+1)begin
                            if(reads[n][j])$display("A54_MMIO phase=%0d read offset=%03x count=%0d",n,j*4,reads[n][j]);
                            if(writes[n][j])$display("A54_MMIO phase=%0d write offset=%03x count=%0d",n,j*4,writes[n][j]);
                        end
                        $display("A54_ENGINE phase=%0d tasks=%0d dots=%0d core_busy=%0d post_items=%0d post_busy=%0d owner_busy=%0d",n,tasks[n],dots[n],core_cycles[n],post_items[n],post_cycles[n],owner_cycles[n]);
                    end
                    $display("A54_RV32_DDR_SOC_PASS quant=%0d block8=%0d",QUANT_ENABLE,BLOCK8_ENABLE);$finish;
                end
            end
            if(phase!=0 && base.dut.u_core.dmem_addr>=32'h40004000 && base.dut.u_core.dmem_addr<32'h40005000)begin
                if(base.dut.u_core.dmem_addr[11:0]>='h300 || base.dut.u_core.dmem_addr[1:0]!=0)$fatal(1,"unexpected AI offset");
                index=base.dut.u_core.dmem_addr[9:2];
                if(base.dut.u_core.dmem_we)writes[phase][index]=writes[phase][index]+1;else reads[phase][index]=reads[phase][index]+1;
            end
        end
    end
endmodule
