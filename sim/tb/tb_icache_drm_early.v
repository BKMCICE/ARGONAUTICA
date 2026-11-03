`timescale 1ns/1ps
// Independently generated read-only backing data; compare two modes by transaction,
// not by equal cycles. Includes changing input addresses, invalidate and reset.
module tb_icache_drm_early #(parameter SET_BITS=6, parameter EARLY_READ=0);
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,req=0,invalidate=0,flush_req=0;
    reg [31:0] addr=0,epoch=0;
    wire ready,line_req,line_we,flush_done,hit_event,miss_event;
    wire [31:0] data,line_addr;
    wire [255:0] line_wdata;
    reg [255:0] line_data;
    reg active=0;
    reg [31:0] held_addr=0,held_epoch=0;
    integer delay_left=0;
    wire line_ready=active && delay_left==0;
    rv_icache_drm_early #(.SET_BITS(SET_BITS),.EARLY_READ(EARLY_READ)) dut(
        .clk(clk),.rst_n(rst_n),.invalidate(invalidate),.flush_req(flush_req),.flush_done(flush_done),
        .cpu_req(req),.cpu_addr(addr),.cpu_rdata(data),.cpu_ready(ready),
        .hit_event(hit_event),.miss_event(miss_event),.line_req(line_req),.line_we(line_we),
        .line_addr(line_addr),.line_wdata(line_wdata),.line_rdata(line_data),.line_ready(line_ready));
    function [31:0] expected;
        input [31:0] address,version;
        begin expected=(address ^ 32'h60d74e29)+(version*32'h10203); end
    endfunction
    integer lane;
    always @* for(lane=0;lane<8;lane=lane+1)
        line_data[lane*32 +: 32]=expected(held_addr+lane*4,held_epoch);
    integer hits=0,misses=0,way0=0,way1=0;
    always @(posedge clk) begin
        if(!rst_n) begin active<=0;delay_left<=0; end
        else begin
            if(!active && line_req) begin
                active<=1;held_addr<=line_addr;held_epoch<=epoch;
                delay_left<=1+line_addr[7:5];
            end else if(active && delay_left>0) delay_left<=delay_left-1;
            else if(line_ready) active<=0;
            if(hit_event)hits=hits+1;
            if(miss_event)misses=misses+1;
            if(dut.refill && !dut.pending_victim)way0=way0+1;
            if(dut.refill && dut.pending_victim)way1=way1+1;
            if(line_we || line_wdata!=0)$fatal(1,"Read-only cache writes backing memory");
            if(dut.refill && dut.ram_read)$fatal(1,"Single-port read/refill collision");
            if(active && line_req && line_addr!==held_addr)$fatal(1,"Refill address not held");
        end
    end
    integer responses=0,total_latency=0,last_latency=0,hot_latency=0;
    reg [31:0] digest=32'h811c9dc5;
    task check_response;
        input [31:0] address,version;
        begin
            if(data!==expected(address,version))$fatal(1,"Wrong response addr=%h expected=%h got=%h mode=%d",address,expected(address,version),data,EARLY_READ);
            digest=(digest ^ data)*32'h01000193;
            responses=responses+1;
        end
    endtask
    task finish_request;
        begin @(negedge clk);req=0;invalidate=0;@(posedge clk);#2; end
    endtask
    task read_word;
        input [31:0] address;
        integer n;
        begin
            @(negedge clk);addr=address;req=1;n=0;
            do begin
                @(posedge clk);#2;n=n+1;
                if(n>100)$fatal(1,"Read timed out");
                // After acceptance, changing live CPU address must not change response.
                if(!ready)begin @(negedge clk);addr=address ^ (n*32'h24);end
            end while(!ready);
            check_response(address,epoch);last_latency=n;total_latency=total_latency+n;
            finish_request;
        end
    endtask
    task flush_cache;
        integer n;
        begin
            @(negedge clk);flush_req=1;n=0;
            do begin @(posedge clk);#2;n=n+1;if(n>2*(1<<SET_BITS)+10)$fatal(1,"Flush timed out");end while(!flush_done);
            @(negedge clk);flush_req=0;@(posedge clk);#2;
        end
    endtask
    task invalidate_lookup;
        input [31:0] address;
        integer n;
        begin
            @(negedge clk);addr=address;req=1;
            @(posedge clk);#2;
            @(negedge clk);invalidate=1;epoch=epoch+1;
            @(posedge clk);#2;
            if(ready)$fatal(1,"Invalidated lookup returned stale data");
            @(negedge clk);invalidate=0;n=0;
            do begin @(posedge clk);#2;n=n+1;if(n>100)$fatal(1,"Invalidate retry timed out");end while(!ready);
            check_response(address,epoch);finish_request;
        end
    endtask
    task reset_during_fill;
        begin
            @(negedge clk);req=1;addr=32'h80007500;
            wait(line_req);@(negedge clk);rst_n=0;req=0;
            repeat(2)@(negedge clk);
            rst_n=1;epoch=epoch+1;read_word(32'h80007500);
        end
    endtask
    task invalidate_fill_edge;
        integer n;
        reg [31:0] version;
        begin
            @(negedge clk);req=1;addr=32'h8000a180;version=epoch;
            wait(line_ready && line_req);
            @(negedge clk);invalidate=1;epoch=epoch+1;
            @(posedge clk);#2;
            if(!ready)$fatal(1,"Fill response missing on invalidate edge");
            check_response(32'h8000a180,version);finish_request;
            // Fill returned its accepted memory version but must NOT leave a valid line.
            read_word(32'h8000a180);
        end
    endtask
    reg [31:0] random_state=32'h60aa18f3;
    integer i;
    initial begin
        #1;rst_n=1;#1;rst_n=0;#1;rst_n=1;
        for(i=0;i<8;i=i+1)read_word(32'h80000000+i*4);
        read_word(32'h80000000+(1<<(SET_BITS+5)));
        read_word(32'h80000000);
        read_word(32'h80000000+(2<<(SET_BITS+5)));
        read_word(32'h80000000+(1<<(SET_BITS+5)));
        for(i=0;i<512;i=i+1)begin
            random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
            read_word(32'h80000000+((random_state&32'h3ff)<<2));
        end
        flush_cache;
        @(negedge clk);invalidate=1;epoch=epoch+1;
        @(posedge clk);#2;@(negedge clk);invalidate=0;
        read_word(32'h80000000);invalidate_lookup(32'h80000000);
        reset_during_fill;invalidate_fill_edge;
        read_word(32'h8000a180);
        for(i=0;i<256;i=i+1)begin read_word(32'h8000a180);hot_latency=hot_latency+last_latency;end
        if(hot_latency!=(EARLY_READ ? 2 : 3)*256)$fatal(1,"Unexpected warm-hit latency %d",hot_latency);
        if(way0==0 || way1==0)$fatal(1,"Both cache ways not covered");
        $display("EARLY_CACHE_PASS mode=%0d set_bits=%0d responses=%0d digest=%08x hits=%0d misses=%0d total_read_latency=%0d hot_reads=256 hot_latency=%0d way0=%0d way1=%0d",EARLY_READ,SET_BITS,responses,digest,hits,misses,total_latency,hot_latency,way0,way1);
        $finish;
    end
    initial begin #10000000;$fatal(1,"Global timeout");end
endmodule
