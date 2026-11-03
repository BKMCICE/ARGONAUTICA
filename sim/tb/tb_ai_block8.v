// Generated full-capacity variant of reviewed original block protocol test.
`timescale 1ns/1ps
module tb_ai_block8;
    reg clk=0,rst_n=0,req=0,we=0;
    reg [3:0] be=15;
    reg [31:0] addr=0,wdata=0;
    wire [31:0] rdata;wire ready;
    ai_conv3x3 #(.ENABLE_BLOCK(1),.ENABLE_BLOCK8(1)) dut(.*);
    always #5 clk=~clk;
    integer cases=0,dots=0,pi,oc,bi,li,ti,ni,np,no,nb,last,pat,c,expected;
    reg [31:0] v,st,clocks,ops;
    reg [31:0] pack0,pack1,pack2;
    function integer sample(input integer i,input integer pattern);
        begin case(pattern)
            0:sample=0;1:sample=(i&1)?127:-128;2:sample=-128;3:sample=127;
            4:sample=((i*73+19)&255)-128;default:sample=((i*109+201)&255)-128;
        endcase end
    endfunction
    task wrmask(input [31:0] off,input [31:0] value,input [3:0] mask);
        begin @(negedge clk);req=1;we=1;addr=off;wdata=value;be=mask;
            @(negedge clk);req=0;we=0;be=15;end
    endtask
    task wr(input [31:0] off,input [31:0] value);begin wrmask(off,value,15);end endtask
    task rd(input [31:0] off,output [31:0] value);
        begin @(negedge clk);req=1;we=0;addr=off;#1;value=rdata;
            if(!ready) $fatal(1,"MMIO not ready");@(negedge clk);req=0;end
    endtask
    task reset_unit;
        begin @(negedge clk);req=0;we=0;rst_n=0;repeat(3) @(negedge clk);rst_n=1;end
    endtask
    task wait_done(input integer want_error);
        integer timeout;
        begin timeout=0;st=0;
            while(!st[1] && timeout<3000) begin rd('h104,st);timeout=timeout+1;end
            if(st!==(want_error?6:2)) $fatal(1,"Status %h expected error=%0d",st,want_error);
        end
    endtask
    task reject_shape(input [31:0] shape_value);
        begin wr('h104,4);wr('h108,shape_value);wr('h104,1);wait_done(1);
            rd('h124,v);if(v!=0) $fatal(1,"Invalid shape ran");end
    endtask
    task upload;
        integer o,b,p,l,ch,t;
        begin wr('h104,4);wr('h10c,0);
            for(o=0;o<no;o=o+1) for(b=0;b<nb;b=b+1) begin
                pack0=0;pack1=0;pack2=32'hd5c3a500;
                for(l=0;l<9;l=l+1) begin
                    t=sample(o*225+b*9+l+11,pat);
                    if(l<4) pack0=pack0|((t&255)<<(l*8));
                    else if(l<8) pack1=pack1|((t&255)<<((l-4)*8));
                    else pack2=pack2|(t&255);
                end
                wr('h110,pack0);wr('h110,pack1);wr('h110,pack2);
            end
            wr('h114,0);
            for(b=0;b<nb;b=b+1) for(p=0;p<np;p=p+1) begin
                pack0=0;pack1=0;pack2=32'h7ec4af00;
                for(l=0;l<9;l=l+1) begin
                    t=sample((b*9+l)*8+p,pat);
                    if(l<4) pack0=pack0|((t&255)<<(l*8));
                    else if(l<8) pack1=pack1|((t&255)<<((l-4)*8));
                    else pack2=pack2|(t&255);
                end
                wr('h118,pack0);wr('h118,pack1);wr('h118,pack2);
            end
            wr('h108,np|(no<<4)|(nb<<8)|(last<<16));
        end
    endtask
    task check_results;
        integer o,p,ch,nchannels;
        begin nchannels=(nb-1)*9+last;wr('h11c,0);
            for(o=0;o<no;o=o+1) for(p=0;p<np;p=p+1) begin
                expected=0;
                for(ch=0;ch<nchannels;ch=ch+1)
                    expected=expected+sample(ch*8+p,pat)*sample(o*225+ch+11,pat);
                rd('h120,v);if($signed(v)!==expected) $fatal(1,"Result %0d expected %0d shape=%0d/%0d/%0d/%0d",$signed(v),expected,np,no,nb,last);
            end
            rd('h11c,v);if(v!=np*no)$fatal(1,"Result cursor/count wrapped");
            rd('h120,v);if(v!=0)$fatal(1,"Result overread exposed data");
            rd('h104,v);if(!v[2])$fatal(1,"Result overread missing error");
            rd('h124,clocks);rd('h128,ops);
            if(clocks!=3*np*no*nb || ops!=np*no*nb) $fatal(1,"Incorrect cycle/dot counters");
        end
    endtask
    initial begin
        reset_unit();rd('h28,v);if(v!='h41333331)$fatal(1,"A33 capability");rd('h100,v);if(v!='h41303131) $fatal(1,"ID mismatch");
        reject_shape(0);reject_shape('h90000|'h19148); // 225 channels
        reject_shape('h10000|'h10119); // nine pixels
        reject_shape('h10000|'h10191); // nine outputs
        reject_shape('ha0000|'h10111); // ten tail lanes
        reject_shape('h10000|'h11); // zero blocks
        reject_shape('h10000|'h10110); // zero pixels
        reject_shape('h10000|'h10101); // zero outputs
        reject_shape('h10000|'h11a11); // twenty-six blocks
        reject_shape('h00110111); // reserved bit20
        // Missing and partially uploaded buffers must never expose RAM contents.
        wr('h104,4);wr('h108,'h10111);wr('h104,1);wait_done(1);rd('h128,v);if(v!=0) $fatal(1,"Uninitialized multiply");
        wr('h10c,0);wr('h110,32'h01010101);wr('h104,1);wait_done(1);
        wr('h110,32'h01010101);wr('h110,1);wr('h104,1);wait_done(1);
        wr('h114,0);wr('h118,32'h01010101);wr('h118,32'h01010101);wr('h118,1);
        wr('h104,1);wait_done(0);wr('h11c,0);rd('h120,v);if(v!=1) $fatal(1,"Single lane");
        rd('h120,v);if(v!=0) $fatal(1,"Result overread returned data");rd('h104,v);if(!v[2]) $fatal(1,"Result overread no error");
        wr('h104,4);wrmask('h108,0,1);rd('h104,v);if(!v[2]) $fatal(1,"Partial write accepted");
        wr('h104,4);wr('h10c,200);wr('h114,200);wr('h11c,64);rd('h104,v);if(!v[2]) $fatal(1,"Out of range accepted");
        wr('h104,4);rd('h121,v);if(v!=0) $fatal(1,"Unaligned read");rd('h104,v);if(!v[2]) $fatal(1,"Unaligned read no error");
        wr(28,32'h7fffffff); // Legacy bias must not leak into raw block sums.
        for(ni=0;ni<4;ni=ni+1) begin
            case(ni) 0:np=1;1:np=2;2:np=7;3:np=8;endcase
            for(no=1;no<=8;no=no+1) for(bi=0;bi<5;bi=bi+1) begin
                case(bi) 0:nb=1;1:nb=2;2:nb=3;3:nb=24;4:nb=25;endcase
                for(last=1;last<=9;last=last+1) if(nb!=25 || last!=9) begin
                    pat=cases%6;upload();wr('h104,1);wait_done(0);check_results();
                    cases=cases+1;dots=dots+np*no*nb;
                end
            end
        end
        // At maximum shape, illegal writes must not change the running command.
        no=8;np=8;nb=25;last=8;pat=5;upload();wr('h104,1);
        wr(0,1);wr('h110,0);wr('h114,0);wr('h108,0);wr('h104,1);wr('h104,4);
        rd('h120,v);if(v!=0) $fatal(1,"Busy result read exposed old data");
        wait_done(1);check_results();
        wr('h104,4);wr('h104,1);repeat(10) @(negedge clk);reset_unit();
        rd('h104,v);if(v!=0) $fatal(1,"Reset left state");
        wr('h108,'h10111);wr('h104,1);wait_done(1);rd('h128,v);if(v!=0) $fatal(1,"Reset preserved validity");
        // Legacy operation after a block abort/reset shares the same multiplier bank.
        wr('h104,4);wr(4,1);wr(8,0);wr(12,0);wr(16,1);wr(20,0);wr(24,0);wr(28,0);wr(0,1);
        repeat(5) @(negedge clk);rd('h24,v);if(v!=1) $fatal(1,"Legacy raw compatibility");
        $display("A33_BLOCK8_RTL_PASS cases=%0d dots=%0d tail_mask=PASS errors_busy_reset=PASS legacy=PASS",cases,dots);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Global timeout");end
endmodule
