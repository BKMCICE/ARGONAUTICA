`timescale 1ns/1ps
// Frozen pre-A39 reference is supplied by the runner. All three backends
// see the same CPU/backing events. Independent CHW-free word/byte ledger
// additionally checks legal transactions and complete dirty flush contents.
module tb_dcache_tags #(parameter SET_BITS=6);
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,invalidate=0,flush_req=0,req=0,we=0;
    reg [3:0] be=15;
    reg [31:0] addr=0,wdata=0;
    wire [31:0] old_data,old_addr;
    wire old_ready,old_hit,old_miss,old_req,old_we,old_flush;
    wire [255:0] old_wdata;
    wire [31:0] got_data[0:2],got_addr[0:2];
    wire got_ready[0:2],got_hit[0:2],got_miss[0:2],got_req[0:2],got_we[0:2],got_flush[0:2];
    wire [255:0] got_wdata[0:2];
    wire [3:0] got_state[0:2];
    reg [255:0] backing[0:1023],ledger[0:1023];
    reg active=0,bus_we=0;
    reg [31:0] bus_addr=0;
    reg [255:0] bus_wdata=0;
    integer delay_left=0;
    wire line_ready=active && delay_left==0;
    wire [255:0] line_data=backing[bus_addr[14:5]];
    rv_cache_2way_reference #(.SET_BITS(SET_BITS)) reference (
        .clk(clk),.rst_n(rst_n),.invalidate(invalidate),.flush_req(flush_req),.flush_done(old_flush),
        .cpu_req(req),.cpu_we(we),.cpu_be(be),.cpu_addr(addr),.cpu_wdata(wdata),
        .cpu_rdata(old_data),.cpu_ready(old_ready),.hit_event(old_hit),.miss_event(old_miss),
        .line_req(old_req),.line_we(old_we),.line_addr(old_addr),.line_wdata(old_wdata),.line_rdata(line_data),.line_ready(line_ready));
    genvar mode;
    generate for(mode=0;mode<3;mode=mode+1)begin : cases
        rv_cache_2way #(.SET_BITS(SET_BITS),.TAG_STORAGE(mode)) dut (
            .clk(clk),.rst_n(rst_n),.invalidate(invalidate),.flush_req(flush_req),.flush_done(got_flush[mode]),
            .cpu_req(req),.cpu_we(we),.cpu_be(be),.cpu_addr(addr),.cpu_wdata(wdata),
            .cpu_rdata(got_data[mode]),.cpu_ready(got_ready[mode]),.hit_event(got_hit[mode]),.miss_event(got_miss[mode]),
            .line_req(got_req[mode]),.line_we(got_we[mode]),.line_addr(got_addr[mode]),.line_wdata(got_wdata[mode]),.line_rdata(line_data),.line_ready(line_ready));
        assign got_state[mode]=dut.state;
        always @(posedge clk) if(rst_n && dut.tag_read_enable && dut.tag_write_enable)
            $fatal(1,"tag read/write collision mode=%0d",mode);
    end endgenerate
    integer checks=0,hits=0,misses=0,writebacks=0,dirty_flush=0,invalid_fill=0,resets=0;
    integer states[0:8],seen_be[0:15];
    integer c;
    always @(posedge clk)begin
        if(!rst_n)begin active<=0;delay_left<=0;end
        else if(!active && old_req)begin
            active<=1;bus_we<=old_we;bus_addr<=old_addr;bus_wdata<=old_wdata;
            delay_left<=1+old_addr[9:5];
        end else if(active && delay_left>0)delay_left<=delay_left-1;
        else if(line_ready)begin
            if(bus_we)backing[bus_addr[14:5]]<=bus_wdata;
            active<=0;
        end
        if(rst_n)begin
            states[reference.state]=states[reference.state]+1;
            if(old_hit)hits=hits+1;
            if(old_miss)misses=misses+1;
            if(old_req && line_ready && old_we)begin
                writebacks=writebacks+1;
                if(reference.state==5)dirty_flush=dirty_flush+1;
            end
            if(invalidate && reference.state==2 && line_ready)invalid_fill=invalid_fill+1;
        end
        #1;
        for(c=0;c<3;c=c+1)begin
            if({old_ready,old_hit,old_miss,old_req,old_we,old_flush} !==
               {got_ready[c],got_hit[c],got_miss[c],got_req[c],got_we[c],got_flush[c]})
                $fatal(1,"tag control mismatch mode=%0d check=%0d oldstate=%0d newstate=%0d",c,checks,reference.state,got_state[c]);
            if(reference.state !== got_state[c])$fatal(1,"state timing mismatch mode=%0d",c);
            if(old_ready && old_data !== got_data[c])$fatal(1,"tag response mismatch mode=%0d",c);
            if(old_req && old_addr !== got_addr[c])$fatal(1,"line address mismatch mode=%0d old=%h got=%h state=%0d",c,old_addr,got_addr[c],reference.state);
            if(old_req && old_we && old_wdata !== got_wdata[c])$fatal(1,"dirty line data mismatch mode=%0d",c);
        end
        checks=checks+1;
    end
    task drain;
        integer n;
        begin
            @(negedge clk);req=0;invalidate=0;flush_req=0;n=0;
            while(reference.state!=0 || active)begin
                @(posedge clk);#2;n=n+1;if(n>20000)$fatal(1,"drain timeout");
            end
        end
    endtask
    task access;
        input [31:0] address,value;
        input is_write;
        input [3:0] lanes;
        reg [31:0] expected;
        integer n,b;
        begin
            @(negedge clk);addr=address;we=is_write;be=lanes;wdata=value;req=1;
            expected=ledger[address[14:5]][address[4:2]*32 +: 32];n=0;
            do begin @(posedge clk);#2;n=n+1;if(n>200)$fatal(1,"access timeout");end while(!old_ready);
            if(old_data !== expected)$fatal(1,"independent old-word ledger mismatch addr=%h write=%b got=%h expected=%h",address,is_write,old_data,expected);
            if(is_write)begin
                seen_be[lanes]=seen_be[lanes]+1;
                for(b=0;b<4;b=b+1)if(lanes[b])ledger[address[14:5]][address[4:2]*32+b*8 +: 8]=value[b*8 +: 8];
            end
            @(negedge clk);req=0;@(posedge clk);#2;
        end
    endtask
    task flush_and_check;
        integer n,j;
        begin
            drain();@(negedge clk);flush_req=1;
            @(posedge clk);#2;@(negedge clk);flush_req=0;n=0;
            while(!old_flush)begin @(posedge clk);#2;n=n+1;if(n>20000)$fatal(1,"flush timeout");end
            drain();
            for(j=0;j<1024;j=j+1)if(backing[j]!==ledger[j])$fatal(1,"independent complete flush failed line=%0d",j);
        end
    endtask
    reg [31:0] random_state=32'h39acd057;
    task random_next;
        begin random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);end
    endtask
    integer i,k,j;
    initial begin
        for(i=0;i<9;i=i+1)states[i]=0;
        for(i=0;i<16;i=i+1)seen_be[i]=0;
        for(i=0;i<1024;i=i+1)for(j=0;j<8;j=j+1)begin
            backing[i][j*32 +: 32]=32'h39a50000^(i*32+j*4);ledger[i][j*32 +: 32]=32'h39a50000^(i*32+j*4);
        end
        #1;rst_n=1;#1;rst_n=0;#1;rst_n=1;
        // All words, every byte mask, both ways and dirty LRU evictions.
        for(i=0;i<8;i=i+1)access(32'h80000000+i*4,0,0,15);
        for(i=0;i<16;i=i+1)begin access(32'h80000004,32'hc0390081+i,1,i);access(32'h80000004,0,0,15);end
        access(32'h80000000+(1<<(SET_BITS+5)),32'hde00ee39,1,15);
        access(32'h80000000+(2<<(SET_BITS+5)),32'h39123aa5,1,5);
        flush_and_check(); // clean way1 advance path as well as dirty stalls
        flush_and_check(); // entirely clean walk must have identical length
        // Fill both ways of every set, write all words, then flush every tag.
        for(i=0;i<2*(1<<SET_BITS);i=i+1)
            for(j=0;j<8;j=j+1)access(32'h80000000+i*32+j*4,32'h90000000+i*8+j,1,15);
        flush_and_check();
        for(i=0;i<1200;i=i+1)begin
            random_next();
            access(32'h80000000|(random_state&32'h00007ffc),random_state^32'ha5a53939,random_state[16],random_state[23:20]);
            if(i%113==0)flush_and_check();
        end
        flush_and_check();
        // Legal flush-before-invalidate, then backing mutation is observed.
        @(negedge clk);invalidate=1;
        @(posedge clk);#2;@(negedge clk);invalidate=0;
        backing[0]=~backing[0];ledger[0]=backing[0];
        access(32'h80000000,0,0,15);flush_and_check();
        // Protocol stress below intentionally permits dropping dirty data on
        // invalidate/reset; only frozen cycle miter applies, not the ledger.
        @(negedge clk);addr=32'h81017fc0;req=1;we=1;be=11;wdata=32'h56bb39aa;
        wait(reference.state==2 && active && delay_left==0);
        @(negedge clk);invalidate=1;@(posedge clk);#2;
        if(!old_ready)$fatal(1,"invalidate/fill timing not preserved");drain();
        // Cancel accepted requests in LOOKUP/HIT and reset an active miss.
        for(k=0;k<2;k=k+1)begin
            @(negedge clk);addr=32'h80001000;req=1;we=0;
            wait(old_ready);drain();
            @(negedge clk);req=1;addr=32'h80001000;
            wait(reference.state==(k==0?7:8));
            @(negedge clk);invalidate=1;@(posedge clk);#2;drain();
        end
        @(negedge clk);addr=32'h81807fe0;req=1;
        wait(old_req && active);@(negedge clk);rst_n=0;req=0;resets=resets+1;
        #2;if(old_ready || old_req)$fatal(1,"async reset failed");@(negedge clk);rst_n=1;
        for(i=0;i<50000;i=i+1)begin
            @(negedge clk);random_next();req=random_state[0];we=random_state[1];
            be=random_state[8:5];addr=32'h80000000|(random_state&32'h01fffffc);wdata=random_state;
            invalidate=random_state[14:9]==0;flush_req=(i%911==0);
            if(i%4001==0)begin rst_n=0;req=0;resets=resets+1;end
            if(i%4001==1)rst_n=1;
        end
        drain();
        for(i=0;i<9;i=i+1)if(states[i]==0)$fatal(1,"cache state %0d uncovered",i);
        for(i=0;i<16;i=i+1)if(seen_be[i]==0)$fatal(1,"byte enable %0d uncovered",i);
        if(writebacks<10 || dirty_flush<2*(1<<SET_BITS) || invalid_fill==0 || resets<2 || hits<10 || misses<10)$fatal(1,"required cache coverage missing");
        $display("A39_DCACHE_TAGS_CYCLE_AND_LEDGER_PASS bits=%0d checks=%0d hits=%0d misses=%0d writebacks=%0d dirty_flush=%0d invalid_fill=%0d resets=%0d",SET_BITS,checks,hits,misses,writebacks,dirty_flush,invalid_fill,resets);
        $finish;
    end
    initial begin #20000000;$fatal(1,"global timeout");end
endmodule
