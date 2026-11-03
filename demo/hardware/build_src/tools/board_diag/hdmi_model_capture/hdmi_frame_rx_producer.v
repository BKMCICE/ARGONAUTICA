// H04Z HDMI_NN_CENTER_RAW320_V1: fixed 1920x1080 full-source validation.
// Sample the centers of a direct 320x320 grid, retain raw interleaved RGB888.
// x_i=6*i+3; y_j=floor(27*(2*j+1)/16). No filter or range expansion.
// All source pixels, including skipped rows and final row1079, remain checked.
// COMMIT only follows the NEXT source VS after full-source validation.
// epoch rst_n is shared with FIFO, never an independent pointer/source reset.
// On any capture fault stop data and latch fault out of band (FIFO may be full).
module hdmi_frame_rx_producer #(
    parameter integer EXPECT_W=1920,EXPECT_H=1080
)(
    input wire pix_clk,rst_n,enable,
    input wire de,hs,vs,input wire [23:0] rgb,
    output reg record_valid,input wire record_ready,
    output reg [257:0] record,
    output reg [7:0] fault
);
    localparam WAIT_FRAME=0,CAPTURE=1,COMMIT=2,HOLD=3;
    reg [1:0] state=0;
    reg de_d=0,hs_d=0,vs_d=0,line_seen=0;
    wire vs_rise=vs&&!vs_d,hs_rise=hs&&!hs_d,de_fall=!de&&de_d;
    reg [15:0] x=0,y=0;
    reg [31:0] pixels=0;
    reg [16:0] sampled_pixels=0;
    reg [15:0] sample_x=3,sample_y=1;
    // 27/16 starts at quotient1/remainder11. Each next row adds54/16,
    // i.e.3 plus carry from remainder+6; comparator recurrence avoids division.
    reg [3:0] sample_y_phase=11;
    wire take_sample=(x==sample_x)&&(y==sample_y);
    reg [5:0] fill=0;
    reg [255:0] packed_bytes=0;
    // byte 0=R, byte 1=G, byte 2=B; residual 0..2 bytes cross a DATA boundary.
    wire [271:0] merged={16'b0,packed_bytes} |
         ({248'b0,rgb[7:0],rgb[15:8],rgb[23:16]} << (fill*8));
    wire slot_free=!record_valid||record_ready;
    task fail_capture;
        input [7:0] code;
        begin fault<=code;state<=HOLD;record_valid<=0;end
    endtask
    always @(posedge pix_clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=WAIT_FRAME;de_d<=0;hs_d<=0;vs_d<=0;line_seen<=0;
            x<=0;y<=0;pixels<=0;fill<=0;packed_bytes<=0;
            sampled_pixels<=0;sample_x<=3;sample_y<=1;sample_y_phase<=11;
            record_valid<=0;record<=0;fault<=0;
        end else if(enable) begin
            de_d<=de;hs_d<=hs;vs_d<=vs;
            if(record_valid&&record_ready) record_valid<=0;
            // A misparameterized synthesized instance must never emit frame data.
            if(EXPECT_W!=1920||EXPECT_H!=1080) fail_capture(8'h02);
            else case(state)
                WAIT_FRAME: if(vs_rise) begin
                    if(de||de_d) fail_capture(8'h08);
                    else begin
                        state<=CAPTURE;x<=0;y<=0;pixels<=0;fill<=0;
                        packed_bytes<=0;line_seen<=0;
                        sampled_pixels<=0;sample_x<=3;sample_y<=1;sample_y_phase<=11;
                    end
                end
                CAPTURE: if(vs_rise) begin
                    if(de||de_d) fail_capture(8'h08);
                    else if(y!=EXPECT_H||pixels!=EXPECT_W*EXPECT_H||
                            sampled_pixels!=102400||fill!=0)
                        fail_capture(8'h02);
                    else state<=COMMIT;
                end else if(hs_rise&&(de||de_d)) fail_capture(8'h08);
                else if(de && (x>=EXPECT_W||y>=EXPECT_H)) fail_capture(8'h01);
                else if(de&&!de_d&&line_seen&&!hs_rise) fail_capture(8'h08);
                else if(de_fall&&x!=EXPECT_W) fail_capture(8'h01);
                else begin
                    if(hs_rise) line_seen<=0;
                    if(de) begin
                        if(!de_d) line_seen<=1;
                        x<=x+1'b1;pixels<=pixels+1'b1;
                        if(take_sample) begin
                            sampled_pixels<=sampled_pixels+1'b1;
                            sample_x<=sample_x+16'd6;
                            if(fill>=29) begin
                                if(!slot_free) fail_capture(8'h10);
                                else begin
                                    record<={2'b00,merged[255:0]};record_valid<=1;
                                    packed_bytes<={240'b0,merged[271:256]};fill<=fill+3-32;
                                end
                            end else begin packed_bytes<=merged[255:0];fill<=fill+3;end
                        end
                    end
                    if(de_fall) begin
                        x<=0;y<=y+1'b1;sample_x<=3;
                        if(y==sample_y) begin
                            if(sample_y_phase>=10) begin
                                sample_y<=sample_y+16'd4;
                                sample_y_phase<=sample_y_phase-4'd10;
                            end else begin
                                sample_y<=sample_y+16'd3;
                                sample_y_phase<=sample_y_phase+4'd6;
                            end
                        end
                    end
                end
                COMMIT: if(slot_free) begin
                    record<={2'b01,256'b0};record_valid<=1;state<=HOLD;
                end
                default: begin end
            endcase
        end
    end
`ifndef SYNTHESIS
    initial if(EXPECT_W!=1920||EXPECT_H!=1080)
        $fatal(1,"HDMI_NN_CENTER_RAW320_V1 requires exact1920x1080 source");
`endif
endmodule
