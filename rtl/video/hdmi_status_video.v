// 640x480/60-ish RGB status page for the board's parallel-input HDMI TX.
// A 25 MHz pixel clock gives 59.52 Hz with the standard 800x525 totals.
// GPIO_OUT[7] marks inference complete; [6:0] is the COCO class number.
module hdmi_status_video (
    input  wire       pix_clk,
    input  wire       pixel_enable,
    input  wire       rst_n,
    input  wire [7:0] status_code,
    output reg        hs,
    output reg        vs,
    output reg        de,
    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b
);
    reg [9:0] h = 0;
    reg [9:0] v = 0;
    reg [7:0] code_meta = 0;
    reg [7:0] code_sync = 0;
    wire active = h >= 10'd144 && h < 10'd784 &&
                  v >= 10'd35 && v < 10'd515;
    wire [9:0] x = h - 10'd144;
    wire [9:0] y = v - 10'd35;
    wire left_digit = x >= 10'd220 && x < 10'd284 &&
                      y >= 10'd184 && y < 10'd296;
    wire right_digit = x >= 10'd356 && x < 10'd420 &&
                       y >= 10'd184 && y < 10'd296;

    function [6:0] segments;
        input [3:0] value;
        begin
            case (value)
                4'h0: segments = 7'b1111110;
                4'h1: segments = 7'b0110000;
                4'h2: segments = 7'b1101101;
                4'h3: segments = 7'b1111001;
                4'h4: segments = 7'b0110011;
                4'h5: segments = 7'b1011011;
                4'h6: segments = 7'b1011111;
                4'h7: segments = 7'b1110000;
                4'h8: segments = 7'b1111111;
                4'h9: segments = 7'b1111011;
                4'ha: segments = 7'b1110111;
                4'hb: segments = 7'b0011111;
                4'hc: segments = 7'b1001110;
                4'hd: segments = 7'b0111101;
                4'he: segments = 7'b1001111;
                default: segments = 7'b1000111;
            endcase
        end
    endfunction

    function digit_pixel;
        input [3:0] value;
        input [5:0] dx;
        input [6:0] dy;
        reg [6:0] seg;
        begin
            seg = segments(value);
            digit_pixel = (seg[6] && dy < 7'd8 && dx >= 6'd8 && dx < 6'd56) ||
                          (seg[5] && dx >= 6'd56 && dy >= 7'd8 && dy < 7'd56) ||
                          (seg[4] && dx >= 6'd56 && dy >= 7'd56 && dy < 7'd104) ||
                          (seg[3] && dy >= 7'd104 && dx >= 6'd8 && dx < 6'd56) ||
                          (seg[2] && dx < 6'd8 && dy >= 7'd56 && dy < 7'd104) ||
                          (seg[1] && dx < 6'd8 && dy >= 7'd8 && dy < 7'd56) ||
                          (seg[0] && dy >= 7'd52 && dy < 7'd60 && dx >= 6'd8 && dx < 6'd56);
        end
    endfunction

    wire digits_on =
        (left_digit && digit_pixel(code_sync[7:4], x - 10'd220, y - 10'd184)) ||
        (right_digit && digit_pixel(code_sync[3:0], x - 10'd356, y - 10'd184));
    reg [23:0] color;
    always @(*) begin
        color = 24'h101820;
        if (y < 10'd96) begin
            if (!code_sync[7]) color = 24'h17406b;       // waiting: blue
            else if (code_sync == 8'hff) color = 24'h8c2830; // no detection: red
            else color = 24'h186843;                     // detection: green
        end else if (digits_on) color = 24'he8f4ff;
        else if ((x >= 10'd176 && x < 10'd464 &&
                  (y == 10'd152 || y == 10'd328)) ||
                 (y >= 10'd152 && y <= 10'd328 &&
                  (x == 10'd176 || x == 10'd463))) color = 24'h53a7cb;
    end

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            h <= 0;
            v <= 0;
            code_meta <= 0;
            code_sync <= 0;
            hs <= 1;
            vs <= 1;
            de <= 0;
            r <= 0;
            g <= 0;
            b <= 0;
        end else begin
            code_meta <= status_code;
            code_sync <= code_meta;
            if (pixel_enable) begin
            if (h == 10'd799) begin
                h <= 0;
                if (v == 10'd524) v <= 0;
                else v <= v + 1'b1;
            end else h <= h + 1'b1;
            hs <= !(h < 10'd96);
            vs <= !(v < 10'd2);
            de <= active;
            if (active) begin
                r <= color[23:16];
                g <= color[15:8];
                b <= color[7:0];
            end else begin
                r <= 0;
                g <= 0;
                b <= 0;
            end
            end
        end
    end
endmodule
