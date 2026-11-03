`timescale 1ns/1ps
module tb_soc_bus;
    reg req, we;
    reg [3:0] be;
    reg [31:0] addr, wdata;
    reg [7:0] sel, ready;
    reg [255:0] data;
    wire [31:0] rd0, rd1, sa0, sa1, wd0, wd1;
    wire ready0, ready1, fault0, fault1, we0, we1;
    wire [7:0] req0, req1;
    wire [3:0] be0, be1;
    soc_bus #(.N_SLAVES(8)) reference_bus (
        .m_req(req),.m_we(we),.m_be(be),.m_addr(addr),.m_wdata(wdata),
        .m_rdata(rd0),.m_ready(ready0),.m_fault(fault0),.sel(sel),
        .s_req(req0),.s_we(we0),.s_be(be0),.s_addr(sa0),.s_wdata(wd0),
        .s_rdata(data),.s_ready(ready));
    soc_bus #(.N_SLAVES(8),.ONE_HOT_SELECT(1)) parallel_bus (
        .m_req(req),.m_we(we),.m_be(be),.m_addr(addr),.m_wdata(wdata),
        .m_rdata(rd1),.m_ready(ready1),.m_fault(fault1),.sel(sel),
        .s_req(req1),.s_we(we1),.s_be(be1),.s_addr(sa1),.s_wdata(wd1),
        .s_rdata(data),.s_ready(ready));
    integer n, j, choice;
    reg [31:0] seed = 32'h81042026;
    function [31:0] next_random;
        input [31:0] x;
        reg [31:0] v;
        begin v=x^(x<<13); v=v^(v>>17); next_random=v^(v<<5); end
    endfunction
    initial begin
        for (n=0; n<8192; n=n+1) begin
            seed=next_random(seed); addr=seed; req=seed[0]; we=seed[1]; be=seed[5:2];
            seed=next_random(seed); wdata=seed; ready=seed[7:0];
            for (j=0; j<8; j=j+1) begin seed=next_random(seed); data[j*32 +:32]=seed; end
            choice=n%9; sel=choice==8 ? 0 : (8'b1<<choice);
            #1;
            if ({rd0,ready0,fault0,req0,we0,be0,sa0,wd0} !==
                {rd1,ready1,fault1,req1,we1,be1,sa1,wd1})
                $fatal(1,"one-hot bus mismatch sample=%0d sel=%h",n,sel);
        end
        // Legacy/default mode must retain priority for overlapping selects.
        sel=8'h81; ready=8'h80; data[255:224]=32'h12345678; data[31:0]=32'h87654321;
        #1;
        if (rd0 !== 32'h12345678 || ready0 !== 1'b1) $fatal(1,"legacy priority changed");
        $display("SOC_BUS_ONE_HOT_PASS samples=8192 legacy_priority=PASS");
        $finish;
    end
endmodule
