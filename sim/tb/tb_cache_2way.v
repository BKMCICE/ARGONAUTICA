`timescale 1ns/1ps
module tb_cache_2way;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg cpu_req = 0, cpu_we = 0, invalidate = 0;
    reg [3:0] cpu_be = 4'hF;
    reg [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire [31:0] cpu_rdata;
    wire cpu_ready, hit_event, miss_event;
    wire line_req, line_we;
    wire [31:0] line_addr;
    wire [255:0] line_wdata;
    wire [255:0] line_rdata;
    wire line_ready;

    rv_cache_2way dut (
        .clk(clk), .rst_n(rst_n), .invalidate(invalidate),
        .flush_req(1'b0), .flush_done(),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_be(cpu_be),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .hit_event(hit_event), .miss_event(miss_event),
        .line_req(line_req), .line_we(line_we), .line_addr(line_addr),
        .line_wdata(line_wdata), .line_rdata(line_rdata), .line_ready(line_ready)
    );

    reg [255:0] backing [0:255];
    reg [1:0] bus_state = 0;
    reg [2:0] wait_cycles = 0;
    reg [31:0] bus_addr;
    reg [255:0] bus_wdata;
    reg bus_we;
    integer line, word, fills = 0, writebacks = 0, hits = 0, misses = 0;
    initial begin
        for (line = 0; line < 256; line = line + 1)
            for (word = 0; word < 8; word = word + 1)
                backing[line][word*32 +: 32] = (line << 8) | word;
    end
    assign line_ready = bus_state == 2;
    assign line_rdata = backing[bus_addr[12:5]];
    always @(posedge clk) begin
        if (hit_event) hits <= hits + 1;
        if (miss_event) misses <= misses + 1;
        case (bus_state)
            0: if (line_req) begin
                bus_addr <= line_addr;
                bus_wdata <= line_wdata;
                bus_we <= line_we;
                wait_cycles <= 3;
                bus_state <= 1;
            end
            1: if (wait_cycles == 0) bus_state <= 2;
               else wait_cycles <= wait_cycles - 1;
            2: begin
                if (bus_we) begin
                    backing[bus_addr[12:5]] <= bus_wdata;
                    writebacks <= writebacks + 1;
                end else fills <= fills + 1;
                bus_state <= 0;
            end
        endcase
    end

    task access;
        input [31:0] addr;
        input we;
        input [3:0] be;
        input [31:0] data;
        input [31:0] expected;
        integer timeout;
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_we = we;
            cpu_be = be;
            cpu_wdata = data;
            cpu_req = 1;
            timeout = 0;
            do begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 100) $fatal(1, "cache timeout at %h", addr);
            end while (!cpu_ready);
            if (!we && cpu_rdata !== expected)
                $fatal(1, "read %h got %h expected %h", addr, cpu_rdata, expected);
            @(negedge clk);
            cpu_req = 0;
            @(posedge clk);
        end
    endtask

    initial begin
        #22 rst_n = 1;
        access(32'h0000_0000, 0, 4'hF, 0, 32'h0);
        access(32'h0000_0004, 0, 4'hF, 0, 32'h1);
        access(32'h0000_0004, 1, 4'b0010, 32'h0000_AA00, 0);
        access(32'h0000_0004, 0, 4'hF, 0, 32'h0000_AA01);
        if (backing[0][63:32] !== 32'h1) $fatal(1, "write-through occurred");
        access(32'h0000_0800, 0, 4'hF, 0, 32'h0000_4000);
        access(32'h0000_1000, 0, 4'hF, 0, 32'h0000_8000);
        if (backing[0][63:32] !== 32'h0000_AA01) $fatal(1, "dirty eviction failed");
        access(32'h0000_0004, 0, 4'hF, 0, 32'h0000_AA01);
        if (fills !== 4 || writebacks !== 1 || hits !== 3 || misses !== 4)
            $fatal(1, "counts fills=%0d writes=%0d hits=%0d misses=%0d",
                   fills, writebacks, hits, misses);
        $display("CACHE_PASS fills=%0d writebacks=%0d hits=%0d misses=%0d",
                 fills, writebacks, hits, misses);
        $finish;
    end
endmodule
