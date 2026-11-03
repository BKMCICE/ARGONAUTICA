`timescale 1ns/1ps
module tb_ai_q24_post;
    reg clk=0,rst_n=0,start=0,leaky=0;
    reg signed [31:0] acc=0,mult=0,bias=0;
    wire busy,done,error;wire signed [7:0] value;
    ai_q24_post dut(.*);
    always #5 clk=~clk;
    reg [135:0] vectors[0:99999];
    reg [1023:0] filename;
    integer count,i,timeout,errors=0,leaky_count=0;
    initial begin #20000000;$fatal(1,"post watchdog");end
    initial begin
        if(!$value$plusargs("vectors=%s",filename)||!$value$plusargs("count=%d",count)||count<1||count>100000)$fatal(1,"vectors missing");
        $readmemh(filename,vectors,0,count-1);
        repeat(3)@(negedge clk);rst_n=1;
        for(i=0;i<count;i=i+1)begin
            @(negedge clk);{acc,mult,bias,leaky}=vectors[i][135:39];start=1;
            @(negedge clk);start=0;
            // Inputs may change after acceptance; a second start while busy
            // must not replace the accepted request.
            acc=32'h12345678;mult=0;bias=99;leaky=0;
            if(i%17==0)start=1;
            @(negedge clk);start=0;timeout=0;
            while(!done && timeout<12)begin @(negedge clk);timeout=timeout+1;end
            if(!done || busy || error!==vectors[i][8] || (!error && value!==vectors[i][7:0]))
                $fatal(1,"Q24 vector %0d error=%b value=%0d want=%h",i,error,value,vectors[i][8:0]);
            if(error)errors=errors+1;
            if(vectors[i][39])leaky_count=leaky_count+1;
            @(negedge clk);if(done)$fatal(1,"DONE not a pulse");
        end
        @(negedge clk);start=1;acc=-100;mult=8388608;bias=0;leaky=1;
        @(negedge clk);start=0;rst_n=0;@(negedge clk);rst_n=1;
        repeat(10)@(negedge clk);if(done||busy||error)$fatal(1,"reset abort");
        $display("A32_Q24_SCALAR_RTL_PASS cases=%0d rejected=%0d leaky=%0d reset_busy=PASS",count,errors,leaky_count);$finish;
    end
endmodule
