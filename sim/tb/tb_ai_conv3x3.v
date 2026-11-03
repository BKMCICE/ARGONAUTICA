`timescale 1ns/1ps
module tb_ai_conv3x3;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg req = 0, we = 0;
    reg [31:0] addr = 0, wdata = 0;
    wire [31:0] rdata;
    wire ready;
    ai_conv3x3 dut (
        .clk(clk), .rst_n(rst_n), .req(req), .we(we), .be(4'hf),
        .addr(addr), .wdata(wdata), .rdata(rdata), .ready(ready)
    );
    task wr(input [31:0] offset, input [31:0] value);
        begin
            @(negedge clk); req = 1; we = 1; addr = offset; wdata = value;
            @(negedge clk); req = 0; we = 0;
        end
    endtask
    task check(input [31:0] ctrl, input [31:0] expected, input [31:0] raw);
        integer timeout;
        begin
            wr(0, ctrl);
            addr = 0;
            timeout = 0;
            while (!rdata[1] && timeout < 10) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!ready || !rdata[1]) $fatal(1, "AI timeout");
            addr = 32'h20;
            #1;
            if (rdata !== expected)
                $fatal(1, "AI result=%h expected=%h", rdata, expected);
            addr = 32'h24;
            #1;
            if (rdata !== raw)
                $fatal(1, "AI accum=%h expected=%h", rdata, raw);
            wr(0, 4);
            addr = 0;
            #1;
            if (rdata[1]) $fatal(1, "AI done did not clear");
        end
    endtask
    initial begin
        repeat (3) @(negedge clk); rst_n = 1;
        wr(4, 32'h04030201); wr(8, 32'h08070605); wr(12, 9);
        wr(16, 32'h01010101); wr(20, 32'h01010101); wr(24, 1);
        wr(28, -5);
        check(32'h00000101, 20, 40); // (1+...+9-5) >> 1
        wr(4, 32'hffffffff); wr(8, 32'hffffffff); wr(12, 32'hff);
        wr(28, 0);
        check(1, 32'hfffffff7, 32'hfffffff7); // signed result -9
        check(3, 0, 32'hfffffff7); // ReLU leaves raw sum intact
        wr(4, 32'h7f7f7f7f); wr(8, 32'h7f7f7f7f); wr(12, 127);
        wr(16, 32'h7f7f7f7f); wr(20, 32'h7f7f7f7f); wr(24, 127);
        check(1, 127, 145161); // positive saturation
        wr(4, 32'h80808080); wr(8, 32'h80808080); wr(12, 32'h80);
        check(1, 32'hffffff80, -146304); // 9 * (-128) * 127
        $display("AI_CONV_PASS");
        $finish;
    end
endmodule
