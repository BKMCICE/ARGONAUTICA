`timescale 1ns/1ps
// Real private core+adapter+soc_bus+sync RAM+CLINT. Only the GPIO-window
// wait-state register bank and external IRQ wire are controlled fixtures.
module tb_transaction_core;
    parameter IMAGE="";
    `include "core_symbols.vh"
    reg clk=0,rst_n=0;always #5 clk=~clk;
    wire i_req,i_ready,i_fault;wire [31:0] i_addr,i_rdata;
    wire c_req,c_we,c_ready,c_fault,c_owned,c_consume;wire [3:0] c_be;
    wire [31:0] c_addr,c_wdata,c_rdata;
    wire target_req,target_we,target_ready,target_fault;wire [3:0] target_be;
    wire [31:0] target_addr,target_wdata,target_rdata;wire [8:0] core_sel,target_sel,s_req,s_ready;
    wire [287:0] s_rdata;wire s_we;wire [3:0] s_be;wire [31:0] s_addr,s_wdata;
    wire irq_sw,irq_timer;reg irq_external=0;wire ev_trap;
    rv_core #(.ENABLE_M(1),.ENABLE_BTB(1),.TRANSACTIONAL_DMEM(1),.ENABLE_CACHE_FENCE(0),.REGFILE_STORAGE(1)) dut(
        .clk(clk),.rst_n(rst_n),.imem_req(i_req),.imem_addr(i_addr),.imem_rdata(i_rdata),.imem_ready(i_ready),.imem_fault(i_fault),
        .dmem_req(c_req),.dmem_we(c_we),.dmem_be(c_be),.dmem_addr(c_addr),.dmem_wdata(c_wdata),
        .dmem_rdata(c_rdata),.dmem_ready(c_ready),.dmem_fault(c_fault),.dmem_owned(c_owned),.dmem_consume(c_consume),
        .irq_software(irq_sw),.irq_timer(irq_timer),.irq_external(irq_external),
        .ev_instr_retired(),.ev_branch(),.ev_branch_mispred(),.ev_load_use_stall(),.ev_imem_stall(),.ev_dmem_stall(),
        .ev_trap(ev_trap),.fetch_flush(),.fencei_req(),.fencei_done(1'b1),.pipeline_probe_q());
    assign core_sel={4'b0,c_addr[31:12]==20'h40002,c_addr[31:12]==20'h40001,2'b0,c_addr[31:16]==0};
    rv_data_transaction_boundary #(.SELECT_WIDTH(9)) data_transaction(
        .clk(clk),.rst_n(rst_n),.core_req(c_req),.core_we(c_we),.core_be(c_be),.core_addr(c_addr),.core_wdata(c_wdata),.core_sel(core_sel),
        .core_owned(c_owned),.core_ready(c_ready),.core_fault(c_fault),.core_rdata(c_rdata),.core_consume(c_consume),
        .target_req(target_req),.target_we(target_we),.target_be(target_be),.target_addr(target_addr),.target_wdata(target_wdata),.target_sel(target_sel),
        .target_ready(target_ready),.target_fault(target_fault),.target_rdata(target_rdata));
    soc_bus #(.N_SLAVES(9),.ONE_HOT_SELECT(1)) bus(
        .m_req(target_req),.m_we(target_we),.m_be(target_be),.m_addr(target_addr),.m_wdata(target_wdata),
        .m_rdata(target_rdata),.m_ready(target_ready),.m_fault(target_fault),.sel(target_sel),
        .s_req(s_req),.s_we(s_we),.s_be(s_be),.s_addr(s_addr),.s_wdata(s_wdata),.s_rdata(s_rdata),.s_ready(s_ready));
    soc_ram #(.ADDR_WIDTH(14),.INIT_FILE(IMAGE)) ram(
        .clk(clk),.rst_n(rst_n),.i_req(i_req),.i_addr(i_addr),.i_rdata(i_rdata),.i_ready(i_ready),.i_fault(i_fault),
        .d_req(s_req[0]),.d_we(s_we),.d_be(s_be),.d_addr(s_addr),.d_wdata(s_wdata),.d_rdata(s_rdata[0+:32]),.d_ready(s_ready[0]));
    clint clint_real(.clk(clk),.rst_n(rst_n),.req(s_req[4]),.we(s_we),.be(s_be),.addr(s_addr),.wdata(s_wdata),
        .rdata(s_rdata[128+:32]),.ready(s_ready[4]),.msip(irq_sw),.mtip(irq_timer));
    genvar z;generate for(z=0;z<9;z=z+1)begin:unused_slaves
        if(z!=0&&z!=3&&z!=4)begin assign s_rdata[z*32+:32]=0;assign s_ready[z]=0;end
    end endgenerate
    reg [31:0] mock_words[0:63];integer wait_count=0,read_side_effects=0,n;
    reg pass_issued=0;
    assign s_ready[3]=wait_count==3;
    assign s_rdata[96+:32]=mock_words[s_addr[7:2]];
    always @(posedge clk)begin
        if(!rst_n)begin
            wait_count<=0;read_side_effects<=0;pass_issued<=0;
            for(n=0;n<64;n=n+1)mock_words[n]<=32'h11223344;
        end else begin
            if(!s_req[3])wait_count<=0;else if(wait_count<3)wait_count<=wait_count+1;
            if(s_req[3]&&s_ready[3])begin
                if(s_we)begin
                    for(n=0;n<4;n=n+1)if(s_be[n])mock_words[s_addr[7:2]][n*8+:8]<=s_wdata[n*8+:8];
                    if(s_addr==32'h400010fc)begin
                        if(s_wdata!==32'h600d0011)$fatal(1,"core ASM failed code%h pc%h",s_wdata,dut.exmem_pc);
                        pass_issued<=1;
                    end
                end else read_side_effects<=read_side_effects+1;
            end
        end
    end
    integer captures=0,completions=0,consumes=0,load_hold=0,store_hold=0,fault_hold=0;
    integer sw_set=0,sw_clear=0,irq_traps=0,fault_traps=0,external_traps=0,precheck_captures=0;
    reg held=0;reg [32:0] held_response=0;reg pair_tracking=0,pair_pass=0,precheck_injected=0,external_serviced=0;
    always @(negedge clk)begin
        if(!rst_n)begin irq_external=0;precheck_injected=0;end
        else begin
            if(external_serviced)irq_external=0;
            if(!precheck_injected&&dut.exmem_valid&&dut.exmem_pc==PC_CORE_PRECHECK_LOAD&&!c_owned)begin
                irq_external=1;precheck_injected=1;
            end
        end
    end
    always @(posedge clk)if(rst_n)begin
        if(data_transaction.state==0&&c_req)begin
            captures=captures+1;
            if(dut.exmem_pc==PC_CORE_PRECHECK_LOAD)precheck_captures=precheck_captures+1;
        end
        if(data_transaction.state==1&&(target_fault||target_ready))completions=completions+1;
        if(c_consume)begin
            consumes=consumes+1;
            if(!c_owned||!c_ready||!dut.mem_adv)$fatal(1,"consume without actual MEM advance");
        end
        if(c_ready&&dut.muldiv_stall)begin
            if(c_consume)$fatal(1,"MD stall consumed response");
            if(dut.exmem_pc==PC_CORE_LOAD_DIV)load_hold=load_hold+1;
            if(dut.exmem_pc==PC_CORE_IRQ_STORE)store_hold=store_hold+1;
            if(dut.exmem_pc==PC_CORE_FAULT_LOAD)begin
                fault_hold=fault_hold+1;
                if(!c_fault||c_req)$fatal(1,"fault held response did not suppress req independently");
            end
        end
        if(held&&c_ready&&{c_fault,c_rdata}!==held_response)$fatal(1,"response changed before core consumption");
        held=c_ready&&!c_consume;held_response={c_fault,c_rdata};
        if(c_ready&&target_req)$fatal(1,"slave request repeated during held CPU response");
        if(c_consume&&dut.exmem_pc==PC_CORE_PAIR_FIRST)pair_tracking=1;
        if(pair_tracking&&!c_req)$fatal(1,"required no-low-gap sequence did not exercise continuous req");
        if(c_consume&&dut.exmem_pc==PC_CORE_PAIR_SECOND)begin pair_pass=1;pair_tracking=0;end
        if(s_req[4]&&s_we&&s_addr==32'h40002000)begin
            if(s_wdata==1)sw_set=sw_set+1;else if(s_wdata==0)sw_clear=sw_clear+1;
        end
        if(ev_trap)begin
            if(dut.trap_irq)begin
                if(c_owned)$fatal(1,"IRQ canceled owned transaction");
                if(dut.trap_cause==3)irq_traps=irq_traps+1;
                else if(dut.trap_cause==11)begin
                    if(dut.exmem_pc!=PC_CORE_PRECHECK_LOAD||precheck_captures!=0)$fatal(1,"pre-capture IRQ/future-fault policy wrong");
                    external_traps=external_traps+1;external_serviced=1;
                end else $fatal(1,"unexpected IRQ cause");
            end else begin
                if(dut.trap_cause!=5||!c_fault||!c_consume)$fatal(1,"fault response not precisely consumed with trap");
                fault_traps=fault_traps+1;
            end
        end
    end
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        wait(pass_issued);wait(c_consume&&dut.exmem_pc==PC_CORE_PASS_STORE);@(posedge clk);#1;
        if(captures!=completions||completions!=consumes||load_hold<2||store_hold<2||fault_hold<2||!pair_pass||
           sw_set!=1||sw_clear!=1||irq_traps!=1||fault_traps!=2||external_traps!=1||precheck_captures!=1||read_side_effects!=3)
            $fatal(1,"coverage/count fail cap%0d done%0d consume%0d hold%0d/%0d/%0d pair%0d msip%0d/%0d traps%0d/%0d/%0d pre%0d reads%0d",
                captures,completions,consumes,load_hold,store_hold,fault_hold,pair_pass,sw_set,sw_clear,irq_traps,fault_traps,external_traps,precheck_captures,read_side_effects);
        $display("H04R_TRANSACTION_CORE_DIRECTED_PASS captures=%0d target_complete=%0d real_MEM_consume=%0d load_div_hold=%0d store_div_IRQ_hold=%0d fault_div_hold=%0d no_req_low_gap=1 MSIP_store_once=1 precise_faults=2 mret=PASS IRQ_before_future_fault=PASS byte_half_extension=PASS",captures,completions,consumes,load_hold,store_hold,fault_hold);
        $finish;
    end
    initial begin #2000000;$fatal(1,"transaction core timeout pc%h state%0d ready%0d owned%0d",dut.exmem_pc,data_transaction.state,c_ready,c_owned);end
endmodule
