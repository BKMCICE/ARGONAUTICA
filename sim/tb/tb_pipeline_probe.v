`timescale 1ns/1ps
module tb_pipeline_probe;
    reg clk=0, rst_n=1;
    always #5 clk=~clk;
    reg [31:0] pc=0;
    reg [10:0] flags=0;
    wire [25:0] q;
    rv_pipeline_probe dut(.clk(clk),.rst_n(rst_n),.mem_pc(pc),.flags(flags),.sample_q(q));
    integer i;
    reg [31:0] lfsr=32'h12345678;
    reg [25:0] expected;
    initial begin
        #1;rst_n=0;#1;if (q!==0) $fatal(1,"PROBE_RESET_FAIL");
        @(negedge clk);rst_n=1;
        for(i=0;i<4096;i=i+1) begin
            lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
            case (i%4)
                0:pc={16'b0,lfsr[15:2],2'b0};
                1:pc={16'h8000,lfsr[15:2],2'b0};
                2:pc={16'h0001,lfsr[15:2],2'b0};
                3:pc={lfsr[31:2],2'b0};
            endcase
            flags=lfsr[10:0];
            expected={flags,(pc[31:16]==0),pc[15:2]};
            @(posedge clk);#1;
            if(q!==expected) $fatal(1,"PROBE_FIELDS_FAIL");
            @(negedge clk);
        end
        #1;rst_n=0;#1;if(q!==0) $fatal(1,"PROBE_ASYNC_RESET_FAIL");
        $display("PIPELINE_PROBE_PASS 4096 captures, TCM/DDR/high aliases and async reset");
        $finish;
    end
endmodule
