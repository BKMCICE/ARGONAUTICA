`timescale 1ns/1ps
module tb_ai_window_soc #(parameter WINDOW_ENABLE=1);
    tb_soc_ddr #(.ENABLE_AI_BLOCK(1),.ENABLE_AI_WINDOW(WINDOW_ENABLE),.DDR_LINE_ADDR_BITS(16)) base();
    reg [31:0] result_addr,crt_addr,phase_addr;
    integer phase=0,i,n,seen=0;
    integer ctrl[1:2],pix[1:2],weights[1:2],bias[1:2],mode[1:2],cmd[1:2],stage[1:2];
    integer accum[1:2],polls[1:2],cap[1:2],status[1:2],starts[1:2],busy[1:2],adapter[1:2];
    initial begin
        if(!$value$plusargs("block_tohost=%h",result_addr)||!$value$plusargs("crt_tohost=%h",crt_addr)||
           !$value$plusargs("phase_addr=%h",phase_addr))$fatal(1,"Missing symbols");
        for(i=1;i<=2;i=i+1)begin
            ctrl[i]=0;pix[i]=0;weights[i]=0;bias[i]=0;mode[i]=0;cmd[i]=0;stage[i]=0;
            accum[i]=0;polls[i]=0;cap[i]=0;status[i]=0;starts[i]=0;busy[i]=0;adapter[i]=0;
        end
    end
    generate if(WINDOW_ENABLE)begin
        always @(posedge base.clk)if(base.rst_n && phase!=0)begin
            if(base.dut.u_ai.window_engine.u_impl.core.legacy_start)starts[phase]=starts[phase]+1;
            if(base.dut.u_ai.window_engine.u_impl.core_busy)busy[phase]=busy[phase]+1;
            if(base.dut.u_ai.window_engine.u_impl.state!=0)adapter[phase]=adapter[phase]+1;
        end
    end else begin
        always @(posedge base.clk)if(base.rst_n && phase!=0)begin
            if(base.dut.u_ai.block_engine.u_impl.legacy_start)starts[phase]=starts[phase]+1;
            if(base.dut.u_ai.block_engine.u_impl.busy)busy[phase]=busy[phase]+1;
        end
    end endgenerate
    always @(posedge base.clk)if(base.rst_n)begin
        if((base.awvalid&&base.awready&&base.awaddr>=28'd524288)||
           (base.arvalid&&base.arready&&base.araddr>=28'd524288))$fatal(1,"DDR outside 2MiB model");
        if(base.dut.u_core.pc==32'h8000)$fatal(1,"Unexpected trap");
        if(base.dut.u_core.dmem_req && base.dut.u_core.dmem_ready)begin
            if(base.dut.u_core.dmem_we)begin
                if(base.dut.u_core.dmem_addr==phase_addr)begin
                    phase=base.dut.u_core.dmem_wdata;
                    if(phase>2)$fatal(1,"bad phase");
                end
                if(phase!=0)case(base.dut.u_core.dmem_addr)
                    32'h40004000:begin if(base.dut.u_core.dmem_wdata!=1)$fatal(1,"bad start");ctrl[phase]=ctrl[phase]+1;end
                    32'h40004004,32'h40004008,32'h4000400c:pix[phase]=pix[phase]+1;
                    32'h40004010,32'h40004014,32'h40004018:weights[phase]=weights[phase]+1;
                    32'h4000401c:bias[phase]=bias[phase]+1;
                    32'h40004034:mode[phase]=mode[phase]+1;
                    32'h40004038:cmd[phase]=cmd[phase]+1;
                    32'h4000403c:stage[phase]=stage[phase]+1;
                    default:if(base.dut.u_core.dmem_addr>=32'h40004000 && base.dut.u_core.dmem_addr<32'h40005000)$fatal(1,"unexpected AI write");
                endcase
                if(base.dut.u_core.dmem_addr==result_addr && base.dut.u_core.dmem_wdata!=0)begin
                    if(base.dut.u_core.dmem_wdata!=1)$fatal(1,"bad diagnostic result");seen=1;
                end
                if(base.dut.u_core.dmem_addr==crt_addr && base.dut.u_core.dmem_wdata!=0)begin
                    if(!seen||base.dut.u_core.dmem_wdata!=1)$fatal(1,"main/stack failed");
                    for(n=1;n<=2;n=n+1)$display("A31_TRACE phase=%0d ctrl=%0d pix=%0d weights=%0d bias=%0d mode=%0d cmd=%0d stage=%0d accum=%0d polls=%0d cap=%0d status=%0d core_starts=%0d core_busy=%0d adapter_busy=%0d",
                        n,ctrl[n],pix[n],weights[n],bias[n],mode[n],cmd[n],stage[n],accum[n],polls[n],cap[n],status[n],starts[n],busy[n],adapter[n]);
                    $display("A31_RV32_DDR_SOC_PASS window=%0d",WINDOW_ENABLE);$finish;
                end
            end else if(phase!=0)case(base.dut.u_core.dmem_addr)
                32'h40004000:polls[phase]=polls[phase]+1;
                32'h40004024:accum[phase]=accum[phase]+1;
                32'h40004030:cap[phase]=cap[phase]+1;
                32'h40004034:status[phase]=status[phase]+1;
                default:if(base.dut.u_core.dmem_addr>=32'h40004000 && base.dut.u_core.dmem_addr<32'h40005000)$fatal(1,"unexpected AI read");
            endcase
        end
    end
endmodule
