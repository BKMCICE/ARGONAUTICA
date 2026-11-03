`timescale 1ns/1ps
module tb_soc_ddr #(
    parameter DDR_LINE_ADDR_BITS = 11,
    parameter UART_FRAME_CAPACITY = 256,
    parameter ENABLE_BTB = 1,
    parameter ENABLE_AI_BLOCK = 0,
    parameter ENABLE_AI_WINDOW = 0,
    parameter ENABLE_AI_QUANT = 0,
    parameter ENABLE_AI_BLOCK8 = 0,
    parameter CACHE_STATS_SPLIT_COUNTERS = 0,
    parameter ICACHE_DRM = 0,
    parameter ICACHE_EARLY_READ = 0,
    parameter DCACHE_TAG_STORAGE = 0,
    parameter REGFILE_STORAGE = 0
);
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    wire [27:0] awaddr, araddr;
    wire awap, arap, awvalid, arvalid, awready, arready, wready;
    wire [3:0] awid, arid, awlen, arlen;
    wire [255:0] wdata, rdata;
    wire [31:0] wstrb;
    wire rvalid, rlast, uart_txd;
    reg uart_rxd = 1;
    wire [7:0] leds;
    reg [1023:0] hexfile;
    soc_top_ddr #(.ENABLE_BTB(ENABLE_BTB), .ENABLE_AI_BLOCK(ENABLE_AI_BLOCK), .ENABLE_AI_WINDOW(ENABLE_AI_WINDOW), .ENABLE_AI_QUANT(ENABLE_AI_QUANT), .ENABLE_AI_BLOCK8(ENABLE_AI_BLOCK8), .CACHE_STATS_SPLIT_COUNTERS(CACHE_STATS_SPLIT_COUNTERS), .ICACHE_DRM(ICACHE_DRM), .ICACHE_EARLY_READ(ICACHE_EARLY_READ), .DCACHE_TAG_STORAGE(DCACHE_TAG_STORAGE), .REGFILE_STORAGE(REGFILE_STORAGE)) dut (
        .clk(clk), .rst_n(rst_n), .ddr_init_done(1'b1),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd), .gpio_out(leds), .gpio_in(8'hFF),
        .axi_awaddr(awaddr), .axi_awuser_ap(awap), .axi_awuser_id(awid),
        .axi_awlen(awlen), .axi_awready(awready), .axi_awvalid(awvalid),
        .axi_wdata(wdata), .axi_wstrb(wstrb), .axi_wready(wready),
        .axi_araddr(araddr), .axi_aruser_ap(arap), .axi_aruser_id(arid),
        .axi_arlen(arlen), .axi_arready(arready), .axi_arvalid(arvalid),
        .axi_rdata(rdata), .axi_rvalid(rvalid), .axi_rlast(rlast)
    );
    ddr3_native_model #(.LINE_ADDR_BITS(DDR_LINE_ADDR_BITS)) u_ddr (
        .clk(clk), .rst_n(rst_n),
        .axi_awaddr(awaddr), .axi_awlen(awlen), .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_wdata(wdata), .axi_wstrb(wstrb), .axi_wready(wready),
        .axi_araddr(araddr), .axi_arlen(arlen), .axi_arvalid(arvalid), .axi_arready(arready),
        .axi_rdata(rdata), .axi_rvalid(rvalid), .axi_rlast(rlast)
    );

    longint unsigned cycles = 0;
    longint unsigned timeout_cycles = 100000;
    reg ddr_tohost = 0;
    reg [1023:0] uart_frame_file;
    reg [1023:0] ai_frame_file;
    reg [7:0] uart_frame [0:UART_FRAME_CAPACITY-1];
    integer uart_frame_len;
    integer ai_frame_len;
    integer uart_idx;
    integer uart_bit;
    integer check_idx;
    reg uart_fast;
    reg longboot_check;
    reg yolo_full_check;
    reg yolo_entered = 0;
    reg [31:0] yolo_tohost_addr;
    reg expect_bad_hash;
    reg [63:0] tx_tail = 0;
    initial begin
        if ($value$plusargs("uart_frame=%s", uart_frame_file)) begin
            if (!$value$plusargs("uart_len=%d", uart_frame_len))
                $fatal(1, "uart_len is required with uart_frame");
            if (uart_frame_len < 12 || uart_frame_len > UART_FRAME_CAPACITY)
                $fatal(1, "invalid UART frame length");
            $readmemh(uart_frame_file, uart_frame, 0, uart_frame_len - 1);
            wait (rst_n);
            repeat (120000) @(negedge clk); // bootloader banner at 115200 baud
            if (uart_fast) begin
                // Fast path injects into RX FIFO, retaining CPU MMIO, Cache, and
                // DDR behavior. The original serial path still tests UART timing.
                for (uart_idx = 0; uart_idx < uart_frame_len; uart_idx = uart_idx + 1) begin
                    @(negedge clk);
                    while (dut.u_uart.rx_full) @(negedge clk);
                    dut.u_uart.rx_fifo[dut.u_uart.rx_wp[3:0]] = uart_frame[uart_idx];
                    dut.u_uart.rx_wp = dut.u_uart.rx_wp + 5'd1;
                    if ((uart_idx & 16'hffff) == 0 && uart_idx != 0) begin
                        $display("DDR_LONGBOOT_FEED bytes=%0d cycles=%0d", uart_idx, cycles);
                        $fflush();
                    end
                end
            end else begin
                for (uart_idx = 0; uart_idx < uart_frame_len; uart_idx = uart_idx + 1) begin
                    uart_rxd = 0; repeat (868) @(negedge clk);
                    for (uart_bit = 0; uart_bit < 8; uart_bit = uart_bit + 1) begin
                        uart_rxd = uart_frame[uart_idx][uart_bit];
                        repeat (868) @(negedge clk);
                    end
                    uart_rxd = 1; repeat (868) @(negedge clk);
                end
            end
            if (yolo_full_check) begin
                wait (yolo_entered);
                $readmemh(ai_frame_file, uart_frame, 0, ai_frame_len - 1);
                for (uart_idx = 0; uart_idx < ai_frame_len; uart_idx = uart_idx + 1) begin
                    @(negedge clk);
                    while (dut.u_uart.rx_full) @(negedge clk);
                    dut.u_uart.rx_fifo[dut.u_uart.rx_wp[3:0]] = uart_frame[uart_idx];
                    dut.u_uart.rx_wp = dut.u_uart.rx_wp + 5'd1;
                    if ((uart_idx & 32'hffff) == 0 && uart_idx != 0) begin
                        $display("DDR_YOLO_IMAGE_FEED bytes=%0d cycles=%0d", uart_idx, cycles);
                        $fflush();
                    end
                end
            end
        end
    end
    longint unsigned next_heartbeat = 1000000;
    longint unsigned heartbeat_step = 1000000;
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (expect_bad_hash && dut.u_core.pc[31:28] == 4'h8)
            $fatal(1, "bad checksum image was executed");
        if ((longboot_check || yolo_full_check) && cycles == next_heartbeat) begin
            $display("DDR_LONGBOOT_HEARTBEAT cycles=%0d bytes=%0d pc=%h rx_count=%0d",
                     cycles, uart_idx, dut.u_core.pc,
                     dut.u_uart.rx_wp - dut.u_uart.rx_rp);
            $fflush();
            next_heartbeat = next_heartbeat + heartbeat_step;
        end
        if ((longboot_check || yolo_full_check) && !yolo_entered &&
            dut.u_core.pc == 32'h8000_0000) begin
            if (uart_frame_len - 12 > (32 << DDR_LINE_ADDR_BITS))
                $fatal(1, "DDR model smaller than boot payload");
            for (check_idx = 0; check_idx < uart_frame_len - 12; check_idx = check_idx + 1)
                if (u_ddr.mem[check_idx >> 5][(check_idx & 31)*8 +: 8] !== uart_frame[check_idx + 12])
                    $fatal(1, "DDR_LONGBOOT_MISMATCH offset=%0d got=%h expected=%h",
                           check_idx, u_ddr.mem[check_idx >> 5][(check_idx & 31)*8 +: 8],
                           uart_frame[check_idx + 12]);
            $display("DDR_LONGBOOT_PASS bytes=%0d cycles=%0d", uart_frame_len - 12, cycles);
            $fflush();
            if (longboot_check) $finish;
            yolo_entered = 1;
        end
        if (yolo_full_check && yolo_entered && dut.u_core.dmem_req &&
            dut.u_core.dmem_ready && dut.u_core.dmem_we &&
            dut.u_core.dmem_addr == yolo_tohost_addr) begin
            if (dut.u_core.dmem_wdata == 1)
                $display("DDR_YOLO_RTL_PASS cycles=%0d", cycles);
            else
                $display("DDR_YOLO_RTL_FAIL exit=%h cycles=%0d", dut.u_core.dmem_wdata, cycles);
            $finish;
        end
        if (dut.u_uart.req && dut.u_uart.we && dut.u_uart.addr[3:2] == 0 && dut.u_uart.ready) begin
            $write("%c", dut.u_uart.wdata[7:0]);
            tx_tail = {tx_tail[55:0], dut.u_uart.wdata[7:0]};
            if (expect_bad_hash && tx_tail == "BAD HASH") begin
                $display("\nDDR_BOOT_BAD_HASH_PASS bytes=%0d cycles=%0d", uart_frame_len - 12, cycles);
                $finish;
            end
        end
        if (ddr_tohost && dut.u_core.dmem_req && dut.u_core.dmem_ready &&
            dut.u_core.dmem_we && dut.u_core.dmem_addr == 32'h8000_F000) begin
            $display("DDR_CACHE_STATS ihit=%0d imiss=%0d dhit=%0d dmiss=%0d",
                     dut.u_cache_stats.ihits, dut.u_cache_stats.imisses,
                     dut.u_cache_stats.dhits, dut.u_cache_stats.dmisses);
            if (dut.u_core.dmem_wdata == 1)
                $display("DDR_COREMARK_EXIT cycles=%0d", cycles);
            else
                $display("DDR_COREMARK_FAIL exit=%h", dut.u_core.dmem_wdata);
            $finish;
        end
        if (!ddr_tohost && dut.u_boot_ram.d_req && dut.u_boot_ram.d_we &&
            dut.u_boot_ram.d_addr == 32'h0000_F000 && !dut.u_boot_ram.d_pending) begin
            if (dut.u_boot_ram.d_wdata == 1)
                $display("DDR_SOC_PASS cycles=%0d backing_word=%h", cycles,
                         u_ddr.mem[0][31:0]);
            else
                $display("DDR_SOC_FAIL exit=%h pc=%h", dut.u_boot_ram.d_wdata, dut.u_core.pc);
            $finish;
        end
        if (cycles == timeout_cycles) begin
            $display("DDR_SOC_TIMEOUT pc=%h", dut.u_core.pc);
            $finish;
        end
    end
    initial begin
        if (!$value$plusargs("hex=%s", hexfile)) hexfile = "prog.hex";
        if (!$value$plusargs("timeout=%d", timeout_cycles)) timeout_cycles = 100000;
        ddr_tohost = $test$plusargs("ddr_tohost");
        uart_fast = $test$plusargs("uart_fast");
        longboot_check = $test$plusargs("longboot_check");
        yolo_full_check = $test$plusargs("yolo_full_check");
        if (yolo_full_check) begin
            if (!$value$plusargs("yolo_tohost=%h", yolo_tohost_addr))
                $fatal(1, "yolo_tohost is required for full RTL run");
            if (!$value$plusargs("ai_frame=%s", ai_frame_file) ||
                !$value$plusargs("ai_len=%d", ai_frame_len) ||
                ai_frame_len < 4 || ai_frame_len > UART_FRAME_CAPACITY)
                $fatal(1, "ai_frame/ai_len required for full RTL run");
            heartbeat_step = 100000000;
            next_heartbeat = heartbeat_step;
        end
        expect_bad_hash = $test$plusargs("expect_bad_hash");
        if (longboot_check && !uart_fast) $fatal(1, "longboot_check requires uart_fast");
        if (longboot_check && expect_bad_hash) $fatal(1, "boot checks are mutually exclusive");
        if (yolo_full_check && (!uart_fast || longboot_check || expect_bad_hash))
            $fatal(1, "yolo_full_check requires exclusive uart_fast mode");
        $readmemh(hexfile, dut.u_boot_ram.mem);
        #33 rst_n = 1;
    end
endmodule
