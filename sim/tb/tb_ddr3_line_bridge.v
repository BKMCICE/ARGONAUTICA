`timescale 1ns/1ps
module tb_ddr3_line_bridge;
    reg clk = 0, rst_n = 0, ddr_init_done = 0;
    always #5 clk = ~clk;
    reg line_req = 0, line_we = 0;
    reg [31:0] line_addr = 0;
    reg [255:0] line_wdata = 0;
    wire [255:0] line_rdata;
    wire line_ready;
    wire [27:0] axi_awaddr, axi_araddr;
    wire axi_awuser_ap, axi_aruser_ap, axi_awvalid, axi_arvalid;
    wire [3:0] axi_awuser_id, axi_aruser_id, axi_awlen, axi_arlen;
    wire [255:0] axi_wdata;
    wire [31:0] axi_wstrb;
    reg axi_wready = 0, axi_rvalid = 0, axi_rlast = 0;
    reg [255:0] axi_rdata = 0;

    ddr3_line_bridge dut (
        .clk(clk), .rst_n(rst_n), .ddr_init_done(ddr_init_done),
        .line_req(line_req), .line_we(line_we), .line_addr(line_addr),
        .line_wdata(line_wdata), .line_rdata(line_rdata), .line_ready(line_ready),
        .axi_awaddr(axi_awaddr), .axi_awuser_ap(axi_awuser_ap),
        .axi_awuser_id(axi_awuser_id), .axi_awlen(axi_awlen),
        .axi_awready(1'b1), .axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb), .axi_wready(axi_wready),
        .axi_araddr(axi_araddr), .axi_aruser_ap(axi_aruser_ap),
        .axi_aruser_id(axi_aruser_id), .axi_arlen(axi_arlen),
        .axi_arready(1'b1), .axi_arvalid(axi_arvalid),
        .axi_rdata(axi_rdata), .axi_rvalid(axi_rvalid), .axi_rlast(axi_rlast)
    );

    reg [255:0] mem [0:3];
    reg wr_pending = 0, rd_pending = 0;
    reg [2:0] wr_delay = 0, rd_delay = 0;
    reg [27:0] wr_addr, rd_addr;
    integer writes = 0, reads = 0;
    always @(posedge clk) begin
        axi_wready <= 0;
        axi_rvalid <= 0;
        axi_rlast <= 0;
        if (axi_awvalid) begin
            if (axi_awlen != 0 || axi_awaddr[2:0] != 0 || axi_awuser_ap != 0)
                $fatal(1, "invalid native write command");
            wr_addr <= axi_awaddr;
            wr_pending <= 1;
            wr_delay <= 3;
        end
        if (wr_pending) begin
            if (wr_delay != 0) wr_delay <= wr_delay - 1;
            else begin
                axi_wready <= 1;
                if (axi_wstrb != 32'hFFFF_FFFF) $fatal(1, "write strobe");
                mem[wr_addr[4:3]] <= axi_wdata;
                writes <= writes + 1;
                wr_pending <= 0;
            end
        end
        if (axi_arvalid) begin
            if (axi_arlen != 0 || axi_araddr[2:0] != 0 || axi_aruser_ap != 0)
                $fatal(1, "invalid native read command");
            rd_addr <= axi_araddr;
            rd_pending <= 1;
            rd_delay <= 2;
        end
        if (rd_pending) begin
            if (rd_delay != 0) rd_delay <= rd_delay - 1;
            else begin
                axi_rdata <= mem[rd_addr[4:3]];
                axi_rvalid <= 1;
                axi_rlast <= 1;
                reads <= reads + 1;
                rd_pending <= 0;
            end
        end
    end

    task transfer;
        input write_line;
        input [31:0] address;
        input [255:0] payload;
        integer timeout;
        begin
            @(negedge clk);
            line_we = write_line;
            line_addr = address;
            line_wdata = payload;
            line_req = 1;
            timeout = 0;
            do begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 40) $fatal(1, "native transfer timeout");
            end while (!line_ready);
            if (!write_line && line_rdata !== payload)
                $fatal(1, "read mismatch");
            @(negedge clk);
            line_req = 0;
            @(posedge clk);
        end
    endtask

    initial begin
        #22 rst_n = 1;
        repeat (3) @(posedge clk);
        if (axi_awvalid || axi_arvalid) $fatal(1, "command before calibration");
        ddr_init_done = 1;
        transfer(1, 32'h8000_0020, {8{32'hA5C3_1234}});
        transfer(0, 32'h8000_0020, {8{32'hA5C3_1234}});
        if (writes != 1 || reads != 1) $fatal(1, "native handshake count");
        $display("DDR_BRIDGE_PASS writes=%0d reads=%0d", writes, reads);
        $finish;
    end
endmodule
