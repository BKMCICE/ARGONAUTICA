`timescale 1ns/1ps
module tb_hdmi_status_video;
    reg pix_clk = 0;
    always #10 pix_clk = ~pix_clk;
    reg phase = 0;
    always @(posedge pix_clk) phase <= ~phase;
    wire pclk = phase;
    reg rst_n = 0;
    reg [7:0] status_code = 8'h82;
    wire hs, vs, de;
    wire [7:0] r, g, b;
    hdmi_status_video dut (
        .pix_clk(pix_clk), .pixel_enable(!phase),
        .rst_n(rst_n), .status_code(status_code),
        .hs(hs), .vs(vs), .de(de), .r(r), .g(g), .b(b)
    );
    reg [26:0] rising_sample;
    reg sample_valid = 0;
    always @(posedge pclk) begin
        #1;
        rising_sample = {hs, vs, de, r, g, b};
        sample_valid = 1;
    end
    always @(negedge pclk) begin
        #1;
        if (sample_valid && rst_n && {hs, vs, de, r, g, b} !== rising_sample)
            $fatal(1, "HDMI outputs changed at inverted PA sampling edge");
    end
    integer i, active_count, hs_count, vs_count, green_count, digit_count;
    initial begin
        repeat (5) @(negedge pix_clk);
        rst_n = 1;
        @(negedge vs);
        active_count = 0;
        hs_count = 0;
        vs_count = 0;
        green_count = 0;
        digit_count = 0;
        for (i = 0; i < 800*525; i = i + 1) begin
            @(posedge pclk);
            #1;
            if (de) active_count = active_count + 1;
            if (!hs) hs_count = hs_count + 1;
            if (!vs) vs_count = vs_count + 1;
            if (de && {r,g,b} == 24'h186843) green_count = green_count + 1;
            if (de && {r,g,b} == 24'he8f4ff) digit_count = digit_count + 1;
            if (!de && {r,g,b} != 24'h000000) $fatal(1, "RGB outside DE");
        end
        if (active_count != 640*480 || hs_count != 96*525 ||
            vs_count != 2*800 || green_count != 96*640 || digit_count < 100)
            $fatal(1, "HDMI timing/color mismatch active=%0d hs=%0d vs=%0d green=%0d digit=%0d",
                   active_count, hs_count, vs_count, green_count, digit_count);
        status_code = 8'hff;
        repeat (4) @(posedge pclk);
        for (i = 0; i < 800*525; i = i + 1) begin
            @(posedge pclk);
            #1;
            if (de && {r,g,b} == 24'h8c2830) begin
                $display("HDMI_STATUS_PASS active=%0d hs_low=%0d vs_low=%0d green=%0d digits=%0d red_seen=1",
                         active_count, hs_count, vs_count, green_count, digit_count);
                $finish;
            end
        end
        $fatal(1, "no-detection status not shown");
    end
endmodule
