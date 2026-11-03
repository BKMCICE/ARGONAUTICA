`timescale 1ns/1ps
// Frozen pre-A36 rv_cache_2way_reference supplied by the validation runner.
// Legal read-only CPU stream; default D-cache/writable cache tested separately.
module tb_icache_drm #(parameter SET_BITS=6);
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, invalidate=0, flush_req=0, req=0;
    reg [31:0] addr=0;
    wire [31:0] old_data, new_data, old_line_addr, new_line_addr;
    wire old_ready,new_ready,old_hit,new_hit,old_miss,new_miss;
    wire old_line_req,new_line_req,old_we,new_we,old_flush,new_flush;
    wire [255:0] old_wdata,new_wdata;
    reg [255:0] line_data;
    reg active=0;
    integer delay_left=0;
    reg [31:0] held_addr=0,epoch=0,held_epoch=0;
    wire line_ready=active && delay_left==0;
    rv_cache_2way_reference #(.SET_BITS(SET_BITS)) reference(
        .clk(clk),.rst_n(rst_n),.invalidate(invalidate),.flush_req(flush_req),.flush_done(old_flush),
        .cpu_req(req),.cpu_we(1'b0),.cpu_be(4'b0),.cpu_addr(addr),.cpu_wdata(32'b0),
        .cpu_rdata(old_data),.cpu_ready(old_ready),.hit_event(old_hit),.miss_event(old_miss),
        .line_req(old_line_req),.line_we(old_we),.line_addr(old_line_addr),.line_wdata(old_wdata),
        .line_rdata(line_data),.line_ready(line_ready));
    rv_icache_drm #(.SET_BITS(SET_BITS)) candidate(
        .clk(clk),.rst_n(rst_n),.invalidate(invalidate),.flush_req(flush_req),.flush_done(new_flush),
        .cpu_req(req),.cpu_addr(addr),.cpu_rdata(new_data),.cpu_ready(new_ready),
        .hit_event(new_hit),.miss_event(new_miss),.line_req(new_line_req),.line_we(new_we),
        .line_addr(new_line_addr),.line_wdata(new_wdata),.line_rdata(line_data),.line_ready(line_ready));
    function [31:0] word_value;
        input [31:0] address,version;
        begin word_value=(address ^ 32'h36a5c729)+version; end
    endfunction
    integer lane;
    always @* for (lane=0;lane<8;lane=lane+1)
        line_data[lane*32 +: 32]=word_value(held_addr+lane*4,held_epoch);
    always @(posedge clk) begin
        if (!rst_n) begin active<=0; delay_left<=0; end
        else if (!active && old_line_req) begin
            active<=1; held_addr<=old_line_addr; held_epoch<=epoch;
            delay_left<=1+old_line_addr[7:5];
        end else if (active && delay_left>0) delay_left<=delay_left-1;
        else if (line_ready) active<=0;
    end
    integer checks=0,hits=0,misses=0,responses=0,invalid_fill=0;
    integer seen_way0=0,seen_way1=0,reset_busy=0;
    integer state_seen[0:8];
    always @(posedge clk) begin
        if (rst_n) begin
            if (old_hit) hits=hits+1;
            if (old_miss) misses=misses+1;
            if (old_ready) responses=responses+1;
            if (candidate.refill && candidate.lookup) $fatal(1,"RAM read/refill collided");
            if (candidate.refill && candidate.pending_victim) seen_way1=seen_way1+1;
            if (candidate.refill && !candidate.pending_victim) seen_way0=seen_way0+1;
            if (invalidate && line_ready && old_line_req) invalid_fill=invalid_fill+1;
            state_seen[reference.state]=state_seen[reference.state]+1;
        end
        #1;
        if ({old_ready,old_hit,old_miss,old_line_req,old_flush,old_we} !==
            {new_ready,new_hit,new_miss,new_line_req,new_flush,new_we})
            $fatal(1,"I-cache control cycle differs check=%0d old_state=%0d new_state=%0d",checks,reference.state,candidate.state);
        if (old_line_req && old_line_addr !== new_line_addr) $fatal(1,"refill address differs");
        if (old_ready && old_data !== new_data) $fatal(1,"response differs old=%h new=%h",old_data,new_data);
        if (old_we || new_we) $fatal(1,"read-only cache wrote backing memory");
        checks=checks+1;
    end
    task read_word;
        input [31:0] address;
        integer n;
        begin
            @(negedge clk);addr=address;req=1;
            n=0;
            do begin @(posedge clk); #2; n=n+1; if(n>80)$fatal(1,"directed timeout"); end while(!new_ready);
            if(new_data !== word_value(address,epoch))$fatal(1,"independent directed value failed addr=%h got=%h",address,new_data);
            @(negedge clk);req=0;
            @(posedge clk);#2;
        end
    endtask
    task drain;
        integer n;
        begin
            @(negedge clk);req=0;invalidate=0;flush_req=0;
            n=0;
            while(reference.state!=0 || active) begin
                @(posedge clk);#2;n=n+1;if(n>1024)$fatal(1,"drain timeout");
            end
        end
    endtask
    reg [31:0] random_state=32'h36a105ef;
    task random_next;
        begin
            random_state=random_state^(random_state<<13);
            random_state=random_state^(random_state>>17);
            random_state=random_state^(random_state<<5);
        end
    endtask
    integer i,k;
    initial begin
        for(i=0;i<9;i=i+1)state_seen[i]=0;
        #1;rst_n=1;#1;rst_n=0;#1;rst_n=1;
        // All words, changing sets, both ways, LRU eviction and old-set hazards.
        for(i=0;i<8;i=i+1)read_word(32'h80000000+i*4);
        for(i=0;i<8;i=i+1)read_word(32'h80000020+i*4);
        read_word(32'h80000000+(1<<(SET_BITS+5)));
        read_word(32'h80000000); // make way0 MRU
        read_word(32'h80000000+(2<<(SET_BITS+5))); // evict way1
        read_word(32'h80000000+(1<<(SET_BITS+5)));
        // Mutate backing data then invalidate: all future reads must refill.
        @(negedge clk);invalidate=1;epoch=32'h12340000;
        @(posedge clk);#2;@(negedge clk);invalidate=0;
        read_word(32'h80000000);read_word(32'h8000001c);
        // Invalidate on the exact fill edge, preserving that response while
        // suppressing installation. Next request must miss and refill again.
        @(negedge clk);addr=32'h80007d40;req=1;
        wait(old_line_req && active && delay_left==0);
        @(negedge clk);invalidate=1;
        @(posedge clk);#2;
        if(!new_ready)$fatal(1,"invalidate/fill changed response timing");
        @(negedge clk);req=0;invalidate=0;@(posedge clk);#2;
        read_word(32'h80007d40);
        @(negedge clk);flush_req=1;
        @(posedge clk);#2;@(negedge clk);flush_req=0;
        wait(new_flush);drain();
        // Cancel LOOKUP/HIT; force a cache miss then reset while DDR waits.
        for(k=0;k<2;k=k+1)begin
            @(negedge clk);addr=32'h80007d40;req=1;
            wait(reference.state==(k==0?7:8));
            @(negedge clk);invalidate=1;
            @(posedge clk);#2;drain();
            read_word(32'h80007d40);
        end
        @(negedge clk);addr=32'h8000fae0;req=1;
        wait(old_line_req && active);
        @(negedge clk);rst_n=0;reset_busy=reset_busy+1;req=0;
        #2;if(new_ready || new_line_req)$fatal(1,"async reset failed");
        @(negedge clk);rst_n=1;
        read_word(32'h8000fae0);
        for(i=0;i<50000;i=i+1)begin
            @(negedge clk);random_next();
            req=random_state[0];invalidate=(random_state[7:2]==0);
            flush_req=(i%997==0);
            addr=32'h80000000|(random_state&32'h00001ffc);
            if(i%3==0)addr=32'h80000000|((random_state&32'h000000fc));
            if(i%4001==0)begin rst_n=0;reset_busy=reset_busy+1;end
            if(i%4001==1)rst_n=1;
        end
        drain();
        if(hits<10 || misses<10 || seen_way0==0 || seen_way1==0 || invalid_fill==0 || reset_busy==0)
            $fatal(1,"required coverage missing");
        for(i=0;i<9;i=i+1)if(i!=1 && i!=5 && state_seen[i]==0)$fatal(1,"state%0d not covered",i);
        $display("A36_ICACHE_CYCLE_EQUIVALENCE_PASS set_bits=%0d checks=%0d hits=%0d misses=%0d responses=%0d invalid_fill=%0d way0=%0d way1=%0d reset_busy=%0d",SET_BITS,checks,hits,misses,responses,invalid_fill,seen_way0,seen_way1,reset_busy);
        $finish;
    end
    initial begin #10000000;$fatal(1,"testbench global timeout");end
endmodule
