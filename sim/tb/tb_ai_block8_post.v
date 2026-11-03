`timescale 1ns/1ps
module tb_ai_block8_post;
    reg clk=0,rst_n=0,req=0,we=0;reg [3:0] be=15;reg [31:0] addr=0,wdata=0;
    wire [31:0] rdata,old_data,primitive_data;wire ready;
    ai_conv3x3 #(.ENABLE_BLOCK(1),.ENABLE_QUANT(1),.ENABLE_BLOCK8(1)) dut(.*);
    ai_conv3x3 #(.ENABLE_BLOCK(1),.ENABLE_BLOCK8(1)) old(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),.addr(addr),.wdata(wdata),.rdata(old_data),.ready());
    ai_conv3x3 original(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),.addr(addr),.wdata(wdata),.rdata(primitive_data),.ready());
    always #5 clk=~clk;
    integer cases=0,items=0,faults=0,i,j,c,p,o,b,word,lane,n,np,no,pat,leaky;
    integer ci,pi,oi,expected,raw[0:63],mw[0:7],bw[0:7];
    reg [31:0] v,st,packed_value,packet,rng=32'ha3201122;
    initial begin #100000000;$fatal(1,"post protocol watchdog");end
    function integer sample(input integer k,input integer pattern);
        begin if(pattern==0)sample=-128;else if(pattern==1)sample=(k&1)?127:-128;else sample=((k*73+19)&255)-128;end
    endfunction
    function signed [63:0] scaled(input signed [63:0] x,input signed [31:0] m);
        reg signed [63:0] product,q;
        begin product=x*m;q=((product<0?-product:product)+8388608)/16777216;scaled=product<0?-q:q;end
    endfunction
    function integer quant(input integer x,input integer m,input integer bias,input integer leak);
        reg signed [63:0] q;
        begin q=scaled(x,m)+bias;if(leak && q<0)q=scaled(q,1677722);
        if(q>127)quant=127;else if(q< -127)quant=-127;else quant=q;end
    endfunction
    task wrm(input [31:0] a,input [31:0] d,input [3:0] mask);
        begin @(negedge clk);req=1;we=1;addr=a;wdata=d;be=mask;@(negedge clk);req=0;we=0;be=15;end
    endtask
    task wr(input [31:0] a,input [31:0] d);begin wrm(a,d,15);end endtask
    task rd(input [31:0] a,output [31:0] d);
        begin @(negedge clk);req=1;we=0;addr=a;#1;d=rdata;
        if(!ready)$fatal(1,"not ready");@(negedge clk);req=0;end
    endtask
    task reset_unit;
        begin @(negedge clk);req=0;we=0;rst_n=0;repeat(3)@(negedge clk);rst_n=1;end
    endtask
    task parameters;
        begin wr('h208,0);
        for(o=0;o<no;o=o+1)begin mw[o]=(o&1)?-16384:8388608;bw[o]=o*13-9;
            wr('h20c,mw[o]);wr('h210,bw[o]);end
        end
    endtask
    task payload;
        begin wr('h104,4);wr('h10c,0);
        for(o=0;o<no;o=o+1)for(b=0;b<(n+8)/9;b=b+1)for(word=0;word<3;word=word+1)begin
            packet=32'hd5c3a500;
            if(word<2)packet=0;
            for(lane=0;lane<4;lane=lane+1)if(word*4+lane<9)
                packet=(packet&~(32'hff<<(lane*8)))|((sample(o*225+b*9+word*4+lane+11,pat)&255)<<(lane*8));
            wr('h110,packet);
        end
        wr('h114,0);
        for(b=0;b<(n+8)/9;b=b+1)for(p=0;p<np;p=p+1)for(word=0;word<3;word=word+1)begin
            packet=word==2?32'h7ec4af00:0;
            for(lane=0;lane<4;lane=lane+1)if(word*4+lane<9)
                packet=(packet&~(32'hff<<(lane*8)))|((sample((b*9+word*4+lane)*8+p,pat)&255)<<(lane*8));
            wr('h118,packet);
        end
        wr('h108,np|(no<<4)|(((n+8)/9)<<8)|(((n-1)%9+1)<<16));end
    endtask
    task wait_done(input integer want_error);
        integer timeout;
        begin timeout=0;st=0;while(!st[1] && timeout<10000)begin rd('h104,st);timeout=timeout+1;end
        if(st!==(want_error?6:2))$fatal(1,"post status=%h want_error=%0d",st,want_error);end
    endtask
    task check_results;
        begin rd('h224,v);if(v!=no*((np+3)/4))$fatal(1,"packed count");
        for(o=0;o<no;o=o+1)begin
            for(p=0;p<np;p=p+1)begin expected=0;for(c=0;c<n;c=c+1)expected=expected+sample(c*8+p,pat)*sample(o*225+c+11,pat);raw[o*np+p]=expected;end
            for(p=0;p<np;p=p+4)begin packed_value=0;
                for(j=0;j<4;j=j+1)if(p+j<np)packed_value=packed_value|((quant(raw[o*np+p+j],mw[o],bw[o],leaky)&255)<<(8*j));
                rd('h220,v);if(v!==packed_value)$fatal(1,"packed %h want %h n/p/o=%0d/%0d/%0d",v,packed_value,n,np,no);
            end
        end
        // Read without a rewind: the postprocessor must have restored raw cursor.
        for(i=0;i<np*no;i=i+1)begin rd('h120,v);if($signed(v)!==raw[i])$fatal(1,"raw interface/cursor changed");end
        rd('h104,v);if(v!=2)$fatal(1,"valid reads caused error");
        rd('h22c,v);if(v!=np*no)$fatal(1,"post item count");
        items=items+np*no;cases=cases+1;end
    endtask
    task qfault;
        begin rd('h200,v);if(!v[2]||v[3])$fatal(1,"not fail closed %h",v);faults=faults+1;end
    endtask
    initial begin
        reset_unit;rd('h28,v);if(v!==32'h41333331||old_data!==32'h41333331)$fatal(1,"A331 changed");rd('h2c,v);if(v!==32'h41343831||old_data!==0||primitive_data!==0)$fatal(1,"unsafe capability");
        rd('h20c,v);if(v!==0)$fatal(1,"uninitialized multiplier read");
        rd('h210,v);if(v!==0)$fatal(1,"uninitialized bias read");
        for(i=0;i<20000;i=i+1)begin @(negedge clk);rng=rng*1664525+1013904223;
            req=rng[0];we=rng[1];be=rng[5:2];addr=(rng>>8)&'hfff;
            if(addr[11:8]==2||addr[11:2]==10'h00b)addr=0;
            wdata=rng^32'haabbccdd;rst_n=i%997!=0;#1;if(rdata!==old_data)$fatal(1,"raw compatibility %0d %h",i,addr);
        end
        reset_unit;
        n=1;np=1;no=1;pat=2;leaky=0;payload;wr('h204,1);wr('h104,1);wait_done(1);qfault;
        wr('h104,4);wr('h208,0);wr('h210,1);qfault;
        wr('h200,4);wrm('h20c,1,3);qfault;
        wr('h200,4);wr('h209,0);qfault;
        wr('h200,4);wr('h208,8);qfault;
        wr('h200,4);wr('h204,4);qfault;
        wr('h200,4);wr('h21c,16);qfault;
        wr('h200,4);rd('h220,v);if(v!=0)$fatal(1,"uninitialized packed data");qfault;
        for(ci=0;ci<4;ci=ci+1)begin
            case(ci)0:n=1;1:n=9;2:n=10;3:n=224;endcase
            for(pi=0;pi<6;pi=pi+1)begin case(pi)0:np=1;1:np=3;2:np=4;3:np=5;4:np=7;5:np=8;endcase
                for(oi=0;oi<6;oi=oi+1)begin case(oi)0:no=1;1:no=3;2:no=4;3:no=5;4:no=7;5:no=8;endcase
                    for(leaky=0;leaky<2;leaky=leaky+1)for(pat=0;pat<3;pat=pat+1)begin
                        wr('h204,1|(leaky<<1));parameters;payload;wr('h104,1);wait_done(0);check_results;
                        // Parameters and weights can remain resident for another tile.
                        wr('h104,4);wr('h104,1);wait_done(0);check_results;
                    end
                end
            end
        end
        rd('h220,v);if(v!=0)$fatal(1,"overread leaked packed data");qfault;
        wr('h104,4);wr('h104,1);wr('h204,0);wait_done(1);qfault; // busy write rejected
        wr('h104,4);wr('h104,1);reset_unit;repeat(20)@(negedge clk);rd('h200,v);if(v!=0)$fatal(1,"reset validity");
        // Deliberate arithmetic overflow, then ensure no packed output is exposed.
        n=1;np=1;no=1;pat=0;payload;wr('h204,1);wr('h208,0);wr('h20c,32'h7fffffff);wr('h210,0);
        // A single -128 * -128 gives Q24 2097152, still valid; force bias overflow.
        wr('h208,0);wr('h20c,32'h7fffffff);wr('h210,32'h7fffffff);wr('h104,1);wait_done(1);qfault;
        $display("A48_BLOCK_POST_PROTOCOL_PASS cases=%0d items=%0d faults=%0d miter=20000 raw_cursor_tail_reset=PASS",cases,items,faults);$finish;
    end
endmodule
