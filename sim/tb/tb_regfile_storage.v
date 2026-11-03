`timescale 1ns/1ps
// Compare frozen pre-A41 RTL plus both backends to an independent 32-word
// architectural ledger, before/after clock edges and during uncommitted bypass.
module tb_regfile_storage;
    reg clk=0,we=0;
    reg [4:0] ra=0,rb=0,wa=0;
    reg [31:0] wd=0;
    wire [31:0] ref1,ref2,got1[0:1],got2[0:1];
    reg [31:0] ledger[0:31];
    rv_regfile_reference reference(.clk(clk),.we(we),.waddr(wa),.wdata(wd),
        .raddr1(ra),.raddr2(rb),.rdata1(ref1),.rdata2(ref2));
    genvar mode;
    generate for(mode=0;mode<2;mode=mode+1)begin : backends
        rv_regfile #(.STORAGE(mode)) dut(.clk(clk),.we(we),.waddr(wa),.wdata(wd),
            .raddr1(ra),.raddr2(rb),.rdata1(got1[mode]),.rdata2(got2[mode]));
    end endgenerate
    integer checks=0,edges=0,writes=0,bypass1=0,bypass2=0,dual=0,zero_writes=0,noedge=0;
    always @(posedge clk) edges=edges+1;
    integer seen_reads[0:31],seen_writes[0:31];
    reg [31:0] expect1,expect2,rng=32'h41f00d73;
    integer m,a,b,c,e,n;
    task check;
        begin
            expect1=ra==0 ? 0 : (we && wa!=0 && wa==ra) ? wd : ledger[ra];
            expect2=rb==0 ? 0 : (we && wa!=0 && wa==rb) ? wd : ledger[rb];
            if(ref1!==expect1 || ref2!==expect2)
                $fatal(1,"frozen regfile disagrees with ledger check=%0d",checks);
            for(m=0;m<2;m=m+1)
                if(got1[m]!==expect1 || got2[m]!==expect2)
                    $fatal(1,"regfile backend=%0d mismatch check=%0d ra=%0d rb=%0d wa=%0d we=%b",m,checks,ra,rb,wa,we);
            checks=checks+1;seen_reads[ra]=seen_reads[ra]+1;seen_reads[rb]=seen_reads[rb]+1;
            if(we && wa!=0 && wa==ra)bypass1=bypass1+1;
            if(we && wa!=0 && wa==rb)bypass2=bypass2+1;
            if(we && wa!=0 && wa==ra && wa==rb)dual=dual+1;
        end
    endtask
    task tick;
        input write_en;
        input [4:0] write_addr,read_a,read_b;
        input [31:0] write_data;
        begin
            clk=0;we=write_en;wa=write_addr;ra=read_a;rb=read_b;wd=write_data;
            #1;check();
            clk=1;
            if(write_en)begin
                seen_writes[write_addr]=seen_writes[write_addr]+1;
                if(write_addr!=0)begin ledger[write_addr]=write_data;writes=writes+1;end
                else zero_writes=zero_writes+1;
            end
            #1;check();
            // Disable bypass without a clock edge: committed storage must be
            // correct, rather than merely observing write data at both ports.
            we=0;#1;check();clk=0;#1;check();
        end
    endtask
    task speculative_bypass;
        input [4:0] target;
        input [31:0] value;
        begin
            we=1;wa=target;wd=value;ra=target;rb=target;#1;check();
            we=0;#1;check();
            wd=~value;we=1;rb=target+1'b1;#1;check();
            we=0;#1;check();noedge=noedge+1;
        end
    endtask
    initial begin
        for(a=0;a<32;a=a+1)begin ledger[a]=0;seen_reads[a]=0;seen_writes[a]=0;end
        #1;
        for(a=0;a<32;a=a+1)for(b=0;b<32;b=b+1)begin ra=a;rb=b;#1;check();end
        // Writes and all read/write-address triples, with write both off/on.
        for(e=0;e<2;e=e+1)for(a=0;a<32;a=a+1)
            for(b=0;b<32;b=b+1)for(c=0;c<32;c=c+1)
                tick(e,a,b,c,32'h41a50000 ^ (a<<15) ^ (b<<7) ^ c);
        // Glitch write enable/data while clock is low AND high, never at a
        // rising edge. A bypass value must disappear unless actually written.
        for(a=0;a<32;a=a+1)begin
            speculative_bypass(a,32'hdead0000+a);
            clk=1;#1;check();speculative_bypass(a,32'hbeef0000+a);
            clk=0;#1;check();
        end
        for(n=0;n<50000;n=n+1)begin
            rng=(rng>>1)^({32{rng[0]}}&32'h80200003);
            tick(rng[31],rng[4:0],rng[9:5],rng[14:10],rng ^ (n*32'h9e3779b9));
            if(n%71==0)speculative_bypass(rng[4:0],~rng);
        end
        we=0;
        for(a=0;a<32;a=a+1)for(b=0;b<32;b=b+1)begin ra=a;rb=b;#1;check();end
        for(a=0;a<32;a=a+1)
            if(seen_reads[a]==0 || seen_writes[a]==0)$fatal(1,"address coverage missing %0d",a);
        if(ledger[0]!==0 || edges!=115568 || writes<10000 || bypass1==0 || bypass2==0 || dual==0 || zero_writes==0 || noedge<700)
            $fatal(1,"regfile coverage incomplete");
        $display("A41_REGFILE_FROZEN_AND_LEDGER_PASS checks=%0d edges=%0d writes=%0d bypass1=%0d bypass2=%0d dual=%0d zero_writes=%0d noedge=%0d",checks,edges,writes,bypass1,bypass2,dual,zero_writes,noedge);
        $finish;
    end
endmodule
