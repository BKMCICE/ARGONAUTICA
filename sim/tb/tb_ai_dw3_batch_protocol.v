`timescale 1ns/1ps
module tb_ai_dw3_batch_protocol;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,req=0,we=0,conflict=0;
    reg [3:0] be=15;
    reg [31:0] addr=0,wdata=0;
    wire [31:0] rdata;
    wire ready,busy;
    ai_dw3_batch dut(.*);
    reg mreq=0,mwe=0;reg [3:0] mbe=15;reg [31:0] ma=0,mw=0;
    wire [31:0] old_data,off_data,on_data;wire old_ready,off_ready,on_ready;
    a53_original_ai_conv3x3 #(.ENABLE_BLOCK(1),.ENABLE_QUANT(1),.ENABLE_BLOCK8(1)) reference_core(
        .clk(clk),.rst_n(rst_n),.req(mreq),.we(mwe),.be(mbe),.addr(ma),.wdata(mw),.rdata(old_data),.ready(old_ready));
    // Omitting ENABLE_A53 checks its default-off behavior.
    ai_conv3x3 #(.ENABLE_BLOCK(1),.ENABLE_QUANT(1),.ENABLE_BLOCK8(1)) off_core(
        .clk(clk),.rst_n(rst_n),.req(mreq),.we(mwe),.be(mbe),.addr(ma),.wdata(mw),.rdata(off_data),.ready(off_ready));
    ai_conv3x3 #(.ENABLE_BLOCK(1),.ENABLE_QUANT(1),.ENABLE_BLOCK8(1),.ENABLE_A53(1)) on_core(
        .clk(clk),.rst_n(rst_n),.req(mreq),.we(mwe),.be(mbe),.addr(ma),.wdata(mw),.rdata(on_data),.ready(on_ready));
    task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
    task put(input [31:0] a,input [31:0] v);begin addr=a;wdata=v;req=1;we=1;tick();req=0;we=0;end endtask
    task prepare;integer r,c;begin
        put('h304,2);put('h308,8);put('h30c,16777216);put('h310,0);put('h314,0);
        for(c=0;c<3;c=c+1)put('h318,'h01010101);
        for(r=0;r<3;r=r+1)begin put('h31c,r*5);for(c=0;c<3;c=c+1)put('h320,'h01010101);end
    end endtask
    task wait_idle;integer n;begin
        n=0;while(busy&&n<600)begin tick();n=n+1;end
        if(busy)$fatal(1,"unbounded busy");
    end endtask
    task require_error;begin
        wait_idle();addr='h304;#1;if(rdata!=4)$fatal(1,"missing sticky error %x",rdata);
        addr='h330;#1;if(rdata!=0)$fatal(1,"partial count exposed");
        addr='h32c;#1;if(rdata!=0)$fatal(1,"partial data exposed");
    end endtask
    integer i;reg [31:0] seed=32'ha5312026;
    function [31:0] next(input [31:0] v);begin next=(v>>1)^((0-(v&1))&32'hd0000001);end endfunction
    initial begin
        tick();rst_n=1;tick();prepare();
        // Hold the completion pulse low: the independent engine watchdog fires.
        force dut.qdone=0;put('h304,1);wait_idle();release dut.qdone;require_error();
        $display("A53_WATCHDOG_PASS limit=512");
        prepare();put('h304,1);
        while(dut.items<1)tick(); // fault after a prior byte was computed
        force dut.qerror=1;wait_idle();release dut.qerror;require_error();
        $display("A53_LATE_ERROR_PASS partial_items=%0d",dut.items);
        // Wrapper ownership blocks legacy writes and poisons the active batch.
        // Load the new engine through its real wrapper, then conflict on PIX0.
        mreq=1;mwe=1;ma='h304;mw=2;tick();
        ma='h308;mw=1;tick();ma='h30c;mw=16777216;tick();ma='h310;mw=0;tick();ma='h314;mw=0;tick();
        for(i=0;i<3;i=i+1)begin ma='h318;mw='h01010101;tick();end
        ma='h31c;mw=0;tick();ma='h320;tick();ma='h31c;mw=5;tick();ma='h320;tick();ma='h31c;mw=10;tick();ma='h320;tick();
        ma='h304;mw=1;tick();ma=4;mw=32'h12345678;#1;
        if(on_core.new_engine.original.req!==0)$fatal(1,"legacy access forwarded during ownership");
        tick();mreq=0;mwe=0;
        if(on_core.new_engine.original.block8_quant_engine.u_impl.core.pix0!==0)$fatal(1,"legacy PIX changed during ownership");
        repeat(20)tick();ma='h304;#1;if(on_data!=4)$fatal(1,"wrapper ownership error missing");
        $display("A53_WRAPPER_OWNERSHIP_PASS");
        rst_n=0;tick();rst_n=1;tick();
        // Per-cycle randomized miter. Default-off: full page. Enabled but idle:
        // every pre-existing address outside the newly owned 0x3xx page.
        for(i=0;i<12000;i=i+1)begin
            seed=next(seed);ma={20'b0,seed[11:2],2'b0};
            if(ma[11:8]==3)ma[11:8]=2; // keep new engine idle during legacy miter
            mw=next(seed);mreq=seed[16];mwe=seed[17];mbe=seed[21:18];#1;
            if(off_data!==old_data||off_ready!==old_ready||on_data!==old_data||on_ready!==old_ready)$fatal(1,"legacy pre-edge miter %x",ma);
            tick();#1;
            if(off_data!==old_data||off_ready!==old_ready||on_data!==old_data||on_ready!==old_ready)$fatal(1,"legacy post-edge miter %x",ma);
        end
        for(i=0;i<256;i=i+1)begin
            ma='h300+i*4;mreq=1;mwe=i[0];mw=seed;seed=next(seed);#1;
            if(off_data!==old_data||off_ready!==old_ready)$fatal(1,"default off whole-page miter");tick();
        end
        $display("A53_PROTOCOL_MITER_PASS cycles=12000 disabled_page_samples=256");$finish;
    end
    initial begin #2000000;$fatal(1,"test timeout");end
endmodule
