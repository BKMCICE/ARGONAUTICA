`timescale 1ns/1ps
module tb_ai_pdata_reuse;
    reg clk=0,rst_n=0,req=0,we=0; reg [3:0] be=15;
    reg [31:0] addr=0,wdata=0; wire [31:0] rdata; wire ready;
    ai_conv3x3 #(.ENABLE_BLOCK(1)) dut(.*);
    always #5 clk=~clk;
    integer np,nb,last,no,seed,b,p,l,o,i,timeout,expected,cases=0,pi,bi,li;
    reg [31:0] words[0:2]; reg [31:0] value,status;
    reg [199:0] saved_valid;
    function integer sample(input integer x,input integer tag);
        sample=((x*73+tag*59)&255)-128;
    endfunction
    task wr(input [31:0] off,input [31:0] data);
        begin @(negedge clk);req=1;we=1;addr=off;wdata=data;
            @(negedge clk);req=0;we=0;end
    endtask
    task rd(input [31:0] off,output [31:0] data);
        begin @(negedge clk);req=1;we=0;addr=off;#1;data=rdata;
            if(!ready)$fatal(1,"Not ready");@(negedge clk);req=0;end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        for(pi=0;pi<3;pi=pi+1)for(bi=0;bi<3;bi=bi+1)for(li=0;li<2;li=li+1)begin
            case(pi)0:np=1;1:np=7;default:np=8;endcase
            case(bi)0:nb=1;1:nb=2;default:nb=25;endcase
            last=li?8:1;
            wr('h104,4);wr('h114,0);
            for(b=0;b<nb;b=b+1)for(p=0;p<np;p=p+1)begin
                words[0]=0;words[1]=0;words[2]=0;
                for(l=0;l<9;l=l+1)
                    words[l/4]=words[l/4]|((sample((b*9+l)*8+p,3)&255)<<(8*(l%4)));
                for(i=0;i<3;i=i+1)wr('h118,words[i]);
            end
            saved_valid=dut.block_engine.u_impl.pixel_valid;
            for(seed=0;seed<3;seed=seed+1)begin
                no=seed==1?1:4;
                wr('h104,4);wr('h10c,0);
                for(o=0;o<no;o=o+1)for(b=0;b<nb;b=b+1)begin
                    words[0]=0;words[1]=0;words[2]=0;
                    for(l=0;l<9;l=l+1)
                        words[l/4]=words[l/4]|((sample(o*225+b*9+l,seed+11)&255)<<(8*(l%4)));
                    for(i=0;i<3;i=i+1)wr('h110,words[i]);
                end
                if(dut.block_engine.u_impl.pixel_valid!==saved_valid)$fatal(1,"ACK/weights cleared PDATA valid");
                wr('h108,np|(no<<4)|(nb<<8)|(last<<16));wr('h104,1);
                status=0;timeout=0;
                while(!status[1]&&timeout<3000)begin rd('h104,status);timeout=timeout+1;end
                if(status!==2)$fatal(1,"Status %h",status);
                wr('h11c,0);
                for(o=0;o<no;o=o+1)for(p=0;p<np;p=p+1)begin
                    expected=0;
                    for(l=0;l<(nb-1)*9+last;l=l+1)
                        expected=expected+sample(l*8+p,3)*sample(o*225+l,seed+11);
                    rd('h120,value);
                    if($signed(value)!==expected)$fatal(1,"PDATA reuse mismatch");
                end
                cases=cases+1;
            end
        end
        $display("A28_PDATA_REUSE_RTL_PASS tasks=%0d ack_retains=PASS changed_weights=PASS output_tail=PASS",cases);$finish;
    end
    initial begin #10000000;$fatal(1,"Timeout");end
endmodule
