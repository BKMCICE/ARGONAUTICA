`timescale 1ns/1ps
module tb_ms7210_init;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    wire hdmi_rst_n, scl, sda, init_done, init_error;
    reg slave_low = 0;
    reg acknowledge = 1;
    assign sda = slave_low ? 1'b0 : 1'bz;
    pullup(sda);
    ms7210_init #(
        .QUARTER_CYCLES(2), .RESET_CYCLES(4),
        .WRITE_GAP_CYCLES(2), .SETTLE_CYCLES(6)
    ) dut (
        .clk(clk), .rst_n(rst_n), .hdmi_rst_n(hdmi_rst_n),
        .scl(scl), .sda(sda), .init_done(init_done), .init_error(init_error)
    );
    integer bits = 0, bytes = 0, starts = 0, stops = 0, transaction_bytes = 0;
    reg active = 0;
    reg [7:0] shift = 0;
    reg [7:0] received;
    // Independently transcribed from the board vendor's control table and
    // IIC transport. In particular, 16-bit register addresses are LOW first.
    reg [7:0] reference_bytes [0:195];
    reg [2047:0] reference_path;
    integer reference_file;
    initial begin
        if (!$value$plusargs("ms7210_reference=%s", reference_path))
            reference_path = "sim/tb/ms7210_reference.hex";
        reference_file = $fopen(reference_path, "r");
        if (!reference_file) $fatal(1, "missing MS7210 vendor reference");
        $fclose(reference_file);
        $readmemh(reference_path, reference_bytes);
    end
    always @(negedge rst_n) begin
        bits = 0;
        bytes = 0;
        starts = 0;
        stops = 0;
        transaction_bytes = 0;
        active = 0;
        slave_low = 0;
    end
    always @(negedge sda) if (scl && hdmi_rst_n) begin
        if (active) $fatal(1, "repeated start");
        active = 1;
        transaction_bytes = 0;
        starts = starts + 1;
    end
    always @(posedge sda) if (scl && hdmi_rst_n && active) begin
        active = 0;
        stops = stops + 1;
    end
    always @(posedge scl) if (active && transaction_bytes < 4) begin
        if (bits < 8) begin
            received = {shift[6:0], sda};
            shift = received;
            if (bits == 7) begin
                if (bytes > 195 || received !== reference_bytes[bytes])
                    $fatal(1, "MS7210 vendor wire byte mismatch index=%0d actual=%02h expected=%02h",
                           bytes, received, reference_bytes[bytes]);
            end
            bits = bits + 1;
        end else begin
            bits = 0;
            bytes = bytes + 1;
            transaction_bytes = transaction_bytes + 1;
        end
    end
    always @(negedge scl) if (active) slave_low = (bits == 8 && acknowledge);
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (init_done || init_error);
        repeat (4) @(negedge clk);
        if (init_error || bytes != 196 || starts != 49 || stops != 49)
            $fatal(1, "MS7210 write sequence failed bytes=%0d starts=%0d stops=%0d", bytes, starts, stops);
        $display("MS7210_ACK_PASS commands=%0d bytes=%0d", starts, bytes);
        rst_n = 0;
        acknowledge = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (init_error || init_done);
        if (!init_error || init_done || bytes != 1 || starts != 1)
            $fatal(1, "MS7210 NACK not detected bytes=%0d starts=%0d", bytes, starts);
        $display("MS7210_NACK_PASS bytes=%0d", bytes);
        $finish;
    end
    initial begin
        repeat (50000) @(posedge clk);
        $fatal(1, "MS7210 test timeout");
    end
endmodule
