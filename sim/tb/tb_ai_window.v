`timescale 1ns/1ps
module tb_ai_window;
    reg clk=0,rst_n=0,req=0,we=0;
    reg [3:0] be=15;
    reg [31:0] addr=0,wdata=0;
    wire [31:0] rdata;wire ready;
    ai_conv3x3 #(.ENABLE_BLOCK(1),.ENABLE_WINDOW(1)) dut(.*);
    wire [31:0] old_data,primitive_data;
    ai_conv3x3 #(.ENABLE_BLOCK(1)) old(.clk(clk),.rst_n(rst_n),.req(req),.we(we),
        .be(be),.addr(addr),.wdata(wdata),.rdata(old_data),.ready());
    ai_conv3x3 original_primitive(.clk(clk),.rst_n(rst_n),.req(req),.we(we),
        .be(be),.addr(addr),.wdata(wdata),.rdata(primitive_data),.ready());
    always #5 clk=~clk;
    initial begin #2000000;$fatal(1,"A31 protocol watchdog");end
    integer i,j,row,k,pattern,stride,dots=0,faults=0,starts=0,busy_cycles=0,before_starts;
    integer p[0:8],w[0:8],expected;
    reg [31:0] v,lo,hi,tail,col0,col1,rng=32'h31fa0201;
    always @(posedge clk) if(rst_n) begin
        if(dut.window_engine.u_impl.core.legacy_start)starts=starts+1;
        if(dut.window_engine.u_impl.core_busy)busy_cycles=busy_cycles+1;
    end
    task wrm(input [31:0] a,input [31:0] d,input [3:0] mask);
        begin @(negedge clk);req=1;we=1;addr=a;wdata=d;be=mask;
        @(negedge clk);req=0;we=0;be=15;end
    endtask
    task wr(input [31:0] a,input [31:0] d);begin wrm(a,d,15);end endtask
    task rd(input [31:0] a,output [31:0] d);
        begin @(negedge clk);req=1;we=0;addr=a;#1;d=rdata;
        if(!ready)$fatal(1,"not ready");@(negedge clk);req=0;end
    endtask
    task reset_unit;
        begin @(negedge clk);req=0;we=0;rst_n=0;repeat(3)@(negedge clk);rst_n=1;end
    endtask
    task seed_window;
        begin lo=0;hi=0;tail=0;
        for(j=0;j<9;j=j+1)begin
            if(j<4)lo=lo|((p[j]&255)<<(8*j));
            else if(j<8)hi=hi|((p[j]&255)<<(8*(j-4)));
            else tail=p[j]&255;
        end
        wr(4,lo);wr(8,hi);wr(12,tail);end
    endtask
    task load_weights;
        begin lo=0;hi=0;tail=0;
        for(j=0;j<9;j=j+1)begin
            if(j<4)lo=lo|((w[j]&255)<<(8*j));
            else if(j<8)hi=hi|((w[j]&255)<<(8*(j-4)));
            else tail=w[j]&255;
        end
        wr(16,lo);wr(20,hi);wr(24,tail);wr(28,-23);end
    endtask
    task check_dot;
        integer timeout;
        begin v=0;timeout=0;
        while(!v[1] && timeout<40)begin rd(0,v);timeout=timeout+1;end
        if(v!=2)$fatal(1,"bad CTRL %h timeout=%0d",v,timeout);
        expected=-23;for(j=0;j<9;j=j+1)expected=expected+p[j]*w[j];
        rd(36,v);if($signed(v)!==expected)$fatal(1,"stale/wrong window dot=%0d want=%0d",$signed(v),expected);
        rd(52,v);if(v!=5)$fatal(1,"bad slide status %h",v);
        dots=dots+1;end
    endtask
    task expect_fault;
        begin rd(52,v);if(!v[1] || v[3:2]!=0)$fatal(1,"missing fail-closed status %h",v);
        faults=faults+1;end
    endtask
    initial begin
        reset_unit;
        rd(48,v);if(v!==32'h41333131||old_data!==0||primitive_data!==0)$fatal(1,"capability probe");
        // Randomized old-register miter: new reserved registers are excluded.
        for(i=0;i<20000;i=i+1)begin
            @(negedge clk);rng=rng*1664525+1013904223;
            req=rng[0];we=rng[1];be=rng[5:2];addr=(rng>>8)&'hfff;
            if(addr[11:4]==3)addr=0;wdata=rng^32'hcafe1234;
            rst_n=(i%997!=0);#1;
            if(rdata!==old_data)$fatal(1,"A02 compatibility cycle=%0d addr=%h",i,addr);
        end
        reset_unit;
        wr(56,0);expect_fault; // disabled
        wr(52,5);wr(56,0);expect_fault; // no complete seed
        wr(52,5);seed_window;wrm(56,0,3);expect_fault;
        wr(52,5);seed_window;wr(57,0);expect_fault;
        wr(52,5);seed_window;wr(56,'h01000000);expect_fault;
        wr(52,5);seed_window;wr(56,'h80000000);expect_fault; // no staged column
        wr(52,5);seed_window;wr(60,'h01000000);expect_fault;
        wr(52,5);seed_window;wr(60,1);wr(60,2);expect_fault;
        wr(52,5);seed_window;wr(60,1);wr(4,0);wr(56,'h80000000);expect_fault;
        wr(52,5);seed_window;wr(60,1);wr(52,5);wr(56,0);expect_fault;
        wr(52,5);seed_window;wr(16,0);wr(56,0);expect_fault;
        wr(52,5);seed_window;wr('h104,4);wr(56,0);expect_fault;
        wr(52,5);seed_window;wr(48,0);expect_fault;
        wr(52,5);seed_window;wr(52,8);expect_fault;
        reset_unit;
        for(pattern=0;pattern<6;pattern=pattern+1)for(stride=1;stride<=2;stride=stride+1)begin
            wr(52,5);
            for(j=0;j<9;j=j+1)begin p[j]=pattern==0?-128:((j*73+pattern*19)&255)-128;
                w[j]=pattern==0?-128:((j*59+pattern*31)&255)-128;end
            load_weights;seed_window;wr(0,1);check_dot;
            for(k=0;k<128;k=k+1)begin
                col0=0;col1=0;
                for(row=0;row<3;row=row+1)begin
                    rng=rng*1664525+1013904223;col0=col0|((rng&255)<<(row*8));
                    rng=rng*1664525+1013904223;col1=col1|((rng&255)<<(row*8));
                    if(stride==1)begin p[row*3]=p[row*3+1];p[row*3+1]=p[row*3+2];
                        p[row*3+2]=$signed(col1[row*8+:8]);end
                    else begin p[row*3]=p[row*3+2];p[row*3+1]=$signed(col0[row*8+:8]);
                        p[row*3+2]=$signed(col1[row*8+:8]);end
                end
                if(stride==2)wr(60,col0);
                wr(56,col1|(stride==2?32'h80000000:0));check_dot;
                if(k%17==0)begin seed_window;wr(0,1);check_dot;end
            end
        end
        // A write while a slide is in flight is rejected, not forwarded.
        before_starts=starts;wr(56,0);wr(28,123456);expect_fault;
        repeat(12)@(negedge clk);if(starts!=before_starts+1)$fatal(1,"busy duplicate start");
        rd(28,v);if($signed(v)!=-23)$fatal(1,"busy write changed bias");
        wr(52,5);seed_window;wr(56,0);reset_unit;repeat(10)@(negedge clk);
        rd(0,v);if(v!=0)$fatal(1,"reset did not abort");rd(52,v);if(v!=0)$fatal(1,"reset retained ownership");
        $display("A31_WINDOW_PROTOCOL_PASS dots=%0d faults=%0d miter=20000 core_starts=%0d core_busy_cycles=%0d",dots,faults,starts,busy_cycles);$finish;
    end
endmodule
