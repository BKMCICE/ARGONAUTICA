`timescale 1ns/1ps
// Real soc_top_ddr, no forced core/cache states. Program drives all control changes.
module tb_soc_fetch_boundary #(parameter ENABLE_BTB=1, parameter READ_WAIT=3, parameter EARLY_READ=0, parameter ENABLE_PIPELINE_PROBE=0);
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    wire [27:0] awaddr,araddr;
    wire awap,arap,awvalid,arvalid,awready,arready,wready;
    wire [3:0] awid,arid,awlen,arlen;
    wire [255:0] wdata,rdata;
    wire [31:0] wstrb;
    wire rvalid,rlast,uart_txd;
    wire [7:0] gpio_out;
    soc_top_ddr #(.ENABLE_BTB(ENABLE_BTB),.ICACHE_DRM(1),.ICACHE_EARLY_READ(EARLY_READ),.DCACHE_TAG_STORAGE(2),.REGFILE_STORAGE(1),.ENABLE_PIPELINE_PROBE(ENABLE_PIPELINE_PROBE)) dut(
        .clk(clk),.rst_n(rst_n),.ddr_init_done(1'b1),.uart_rxd(1'b1),.uart_txd(uart_txd),.gpio_out(gpio_out),.gpio_in(8'hff),
        .axi_awaddr(awaddr),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awready(awready),.axi_awvalid(awvalid),
        .axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wready(wready),.axi_araddr(araddr),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),
        .axi_arready(arready),.axi_arvalid(arvalid),.axi_rdata(rdata),.axi_rvalid(rvalid),.axi_rlast(rlast));
    ddr3_native_latency_model #(.READ_WAIT(READ_WAIT)) memory(
        .clk(clk),.rst_n(rst_n),.axi_awaddr(awaddr),.axi_awlen(awlen),.axi_awvalid(awvalid),.axi_awready(awready),
        .axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wready(wready),.axi_araddr(araddr),.axi_arlen(arlen),.axi_arvalid(arvalid),.axi_arready(arready),
        .axi_rdata(rdata),.axi_rvalid(rvalid),.axi_rlast(rlast));
    integer cycles=0,retired=0,ret_tcm=0,ret_ddr=0,predicted_cross=0,old_fill_redirect=0,replaced_active=0,fences=0;
    integer smc_old=0,smc_new=0,responses=0,phase=0;
    reg [31:0] digest=32'h811c9dc5,expected_word;
    reg [1023:0] hexfile;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(cycles>30000)$fatal(1,"SoC boundary timeout PC=%h phase=%d",dut.u_core.pc,phase);
        if(rst_n)begin
            if(dut.ev_tr)$fatal(1,"Unexpected architectural trap");
            if(dut.ev_ret)begin
                retired=retired+1;
                digest=((digest ^ dut.u_core.exmem_pc)*32'h01000193 ^ dut.u_core.exmem_instr)*32'h01000193;
                $display("A61_RET pc=%08x insn=%08x",dut.u_core.exmem_pc,dut.u_core.exmem_instr);
                if(dut.u_core.exmem_pc[31:30]==2'b10)ret_ddr=ret_ddr+1;else ret_tcm=ret_tcm+1;
                if(dut.u_core.exmem_pc==32'h80001000)begin
                    if(dut.u_core.exmem_instr==32'h01100513)smc_old=smc_old+1;
                    else if(dut.u_core.exmem_instr==32'h06300513)smc_new=smc_new+1;
                    else $fatal(1,"Unexpected self-modified opcode");
                end
            end
            if(dut.imem_req && dut.u_core.btb_hit && dut.u_core.pc[31:30]!=dut.u_core.btb_target[31:30])predicted_cross=predicted_cross+1;
            if(phase==2 && dut.u_core.exmem_pc==32'h00001120 && dut.u_core.mem_redirect && dut.il_req && dut.u_core.mem_redirect_pc[31:30]!=2'b10)
                old_fill_redirect=old_fill_redirect+1;
            if(phase==2 && dut.u_if_adapter.active && dut.u_if_adapter.wanted_valid && dut.u_if_adapter.wanted_addr!=dut.u_if_adapter.active_addr)
                replaced_active=replaced_active+1;
            if(dut.fencei_done)fences=fences+1;
            // Check the consumed response against its captured request PC, not current predicted PC.
            if(dut.u_core.if_adv && dut.u_core.if_instr_valid && !dut.u_core.if_kill && !dut.u_core.skid_valid)begin
                if(dut.i_response_ddr !== (dut.u_core.pc_r[31:30]==2'b10))$fatal(1,"Response routed by wrong address domain");
                if(dut.i_response_ddr)expected_word=memory.mem[dut.u_core.pc_r[15:5]][dut.u_core.pc_r[4:2]*32+:32];
                else expected_word=dut.u_boot_ram.mem[dut.u_core.pc_r[15:2]];
                if(dut.imem_rdata!==expected_word)$fatal(1,"Wrong consumed fetch PC=%h expected=%h got=%h",dut.u_core.pc_r,expected_word,dut.imem_rdata);
                responses=responses+1;
            end
            if(dut.dmem_req && dut.dmem_ready && dut.dmem_we && dut.dmem_addr==32'h0000e000)phase=dut.dmem_wdata;
            if(dut.dmem_req && dut.dmem_ready && dut.dmem_we && dut.dmem_addr==32'h0000f000)begin
                if(dut.dmem_wdata!=1)$fatal(1,"Program failed exit=%d PC=%h",dut.dmem_wdata,dut.u_core.pc);
                if(phase!=4 || dut.u_boot_ram.mem['he004/4]!=32 || dut.u_boot_ram.mem['he008/4]!=0 || dut.u_boot_ram.mem['he00c/4]!=1 || dut.u_boot_ram.mem['he010/4]!=1 || dut.u_boot_ram.mem['he014/4]!=99)
                    $fatal(1,"Architectural result signature differs");
                if(memory.mem[128][31:0]!==32'h06300513)$fatal(1,"FENCE.I did not flush dirty patched code");
                if(smc_old!=2 || smc_new!=1 || fences!=2 || ret_tcm==0 || ret_ddr==0)$fatal(1,"Required execution coverage missing");
                if(ENABLE_BTB && (predicted_cross<2 || old_fill_redirect<1))$fatal(1,"BTB/cold-fill redirect scenario not exercised pred=%d redirect=%d",predicted_cross,old_fill_redirect);
                if(ENABLE_BTB && READ_WAIT>=23 && replaced_active<1)$fatal(1,"Newest DDR request did not replace stale active request");
                $display("A61_SOC_FETCH_BOUNDARY_PASS btb=%0d wait=%0d cycles=%0d retired=%0d digest=%08x tcm=%0d ddr=%0d predicted_cross=%0d old_fill_redirect=%0d replaced_active=%0d fences=%0d smc_old=%0d smc_new=%0d responses=%0d",ENABLE_BTB,READ_WAIT,cycles,retired,digest,ret_tcm,ret_ddr,predicted_cross,old_fill_redirect,replaced_active,fences,smc_old,smc_new,responses);
                $finish;
            end
        end
    end
    initial begin
        if(!$value$plusargs("hex=%s",hexfile))$fatal(1,"TCM HEX required");
        #1;$readmemh(hexfile,dut.u_boot_ram.mem);
        #32;rst_n=1;
    end
endmodule
