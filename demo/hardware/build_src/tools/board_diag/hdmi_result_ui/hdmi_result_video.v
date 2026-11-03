// H18 lightweight HDMI result page. No frame buffer and no new clock.
// Input bundle must already be safely transferred into the pix_clk domain.
// It is copied atomically at h=0,v=0, then remains fixed for the whole frame.
// Timing matches hdmi_status_video: 800x525 totals, 640x480 at 25 MHz CE2.
// phase: 0 waiting, 1 capturing, 2 inference, 3 complete, 4 error.
// classes[8*i+:8] = project COCO class index, scores[10*i+:10] = score_milli.
// count is the number of shown NMS results (current application limit: ten).
// forward_ms is measured FPGA forward time, not end-to-end time or FPS.
module hdmi_result_video (
    input wire pix_clk, pixel_enable, rst_n,
    input wire [7:0] status_code,
    input wire result_valid,
    input wire [2:0] phase,
    input wire [7:0] count,
    input wire [31:0] forward_ms,
    input wire [79:0] classes,
    input wire [99:0] scores,
    output wire frame_start,
    output reg hs, vs, de,
    output reg [7:0] r, g, b
);
    reg [9:0] h=0,v=0;
    reg [7:0] code_meta=0,code_sync=0,code_frame=0;
    reg valid_frame=0;
    reg [2:0] phase_frame=0;
    reg [7:0] count_frame=0;
    reg [31:0] ms_frame=0;
    reg [79:0] classes_frame=0;
    reg [99:0] scores_frame=0;
    assign frame_start=pixel_enable&&(h==0)&&(v==0);
    wire active=h>=144&&h<784&&v>=35&&v<515;
    wire [9:0] x=h-10'd144,y=v-10'd35;
    wire text_area=x>=16&&x<624&&y>=16&&y<464;
    wire [9:0] tx=x-10'd16,ty=y-10'd16;
    wire [5:0] col=tx[9:4],row=ty[9:4];
    wire [2:0] gx=tx[3:1],gy=ty[3:1];
    wire [2:0] shown_phase=valid_frame ? phase_frame :
        (!code_frame[7] ? 3'd0 : 3'd3);

    // One shared iterative binary-to-BCD converter. Formatting completes in
    // 32 SYS50 clocks, well inside vertical blank (35*800*2 SYS50 clocks).
    // No combinational 32-bit divider or multiplier is on the pixel path.
    reg [31:0] time_shift=0;
    reg [39:0] time_work=0,time_bcd=0;
    reg [5:0] time_step=0;
    reg time_busy=0;
    reg [39:0] time_adjust;
    integer j;
    always @* begin
        time_adjust=time_work;
        for(j=0;j<10;j=j+1)
            if(time_work[4*j+:4]>=5)
                time_adjust[4*j+:4]=time_work[4*j+:4]+4'd3;
    end
    always @(posedge pix_clk or negedge rst_n) begin
        if(!rst_n)begin
            time_shift<=0;time_work<=0;time_bcd<=0;time_step<=0;time_busy<=0;
        end else if(frame_start)begin
            time_shift<=forward_ms;time_work<=0;time_step<=0;time_busy<=1;
        end else if(time_busy)begin
            time_work<={time_adjust[38:0],time_shift[31]};
            time_shift<={time_shift[30:0],1'b0};
            if(time_step==31)begin
                time_bcd<={time_adjust[38:0],time_shift[31]};time_busy<=0;
            end else time_step<=time_step+1'b1;
        end
    end

    function [34:0] glyph;
        input [7:0] ch;
        begin
            case(ch)
                8'd32: glyph = 35'b00000000000000000000000000000000000;
                8'd65: glyph = 35'b01110100011000111111100011000110001;
                8'd66: glyph = 35'b11110100011000111110100011000111110;
                8'd67: glyph = 35'b01111100001000010000100001000001111;
                8'd68: glyph = 35'b11110100011000110001100011000111110;
                8'd69: glyph = 35'b11111100001000011110100001000011111;
                8'd70: glyph = 35'b11111100001000011110100001000010000;
                8'd71: glyph = 35'b01111100001000010111100011000101111;
                8'd72: glyph = 35'b10001100011000111111100011000110001;
                8'd73: glyph = 35'b11111001000010000100001000010011111;
                8'd74: glyph = 35'b00111000100001000010100101001001100;
                8'd75: glyph = 35'b10001100101010011000101001001010001;
                8'd76: glyph = 35'b10000100001000010000100001000011111;
                8'd77: glyph = 35'b10001110111010110101100011000110001;
                8'd78: glyph = 35'b10001110011010110011100011000110001;
                8'd79: glyph = 35'b01110100011000110001100011000101110;
                8'd80: glyph = 35'b11110100011000111110100001000010000;
                8'd81: glyph = 35'b01110100011000110001101011001001101;
                8'd82: glyph = 35'b11110100011000111110101001001010001;
                8'd83: glyph = 35'b01111100001000001110000010000111110;
                8'd84: glyph = 35'b11111001000010000100001000010000100;
                8'd85: glyph = 35'b10001100011000110001100011000101110;
                8'd86: glyph = 35'b10001100011000110001100010101000100;
                8'd87: glyph = 35'b10001100011000110101101011010101010;
                8'd88: glyph = 35'b10001100010101000100010101000110001;
                8'd89: glyph = 35'b10001100010101000100001000010000100;
                8'd90: glyph = 35'b11111000010001000100010001000011111;
                8'd48: glyph = 35'b01110100011001110101110011000101110;
                8'd49: glyph = 35'b00100011000010000100001000010001110;
                8'd50: glyph = 35'b01110100010000100010001000100011111;
                8'd51: glyph = 35'b11110000010000101110000010000111110;
                8'd52: glyph = 35'b00010001100101010010111110001000010;
                8'd53: glyph = 35'b11111100001000011110000010000111110;
                8'd54: glyph = 35'b01110100001000011110100011000101110;
                8'd55: glyph = 35'b11111000010001000100010000100001000;
                8'd56: glyph = 35'b01110100011000101110100011000101110;
                8'd57: glyph = 35'b01110100011000101111000010000101110;
                8'd58: glyph = 35'b00000001000010000000001000010000000;
                8'd46: glyph = 35'b00000000000000000000000000011000110;
                8'd45: glyph = 35'b00000000000000011111000000000000000;
                8'd47: glyph = 35'b00001000100001000100010000100010000;
                8'd37: glyph = 35'b11001110100010000100010001011000110;
                8'd62: glyph = 35'b10000010000010000010001000100010000;
                8'd63: glyph = 35'b01110100010000100010001000000000100;
                default: glyph = 35'b01110100010000100010001000000000100;
            endcase
        end
    endfunction

    function [127:0] class_label;
        input [7:0] id;
        begin
            case(id)
                8'd0: class_label = "PERSON          ";
                8'd1: class_label = "BICYCLE         ";
                8'd2: class_label = "CAR             ";
                8'd3: class_label = "MOTORBIKE       ";
                8'd4: class_label = "AEROPLANE       ";
                8'd5: class_label = "BUS             ";
                8'd6: class_label = "TRAIN           ";
                8'd7: class_label = "TRUCK           ";
                8'd8: class_label = "BOAT            ";
                8'd9: class_label = "TRAFFIC LIGHT   ";
                8'd10: class_label = "FIRE HYDRANT    ";
                8'd11: class_label = "STOP SIGN       ";
                8'd12: class_label = "PARKING METER   ";
                8'd13: class_label = "BENCH           ";
                8'd14: class_label = "BIRD            ";
                8'd15: class_label = "CAT             ";
                8'd16: class_label = "DOG             ";
                8'd17: class_label = "HORSE           ";
                8'd18: class_label = "SHEEP           ";
                8'd19: class_label = "COW             ";
                8'd20: class_label = "ELEPHANT        ";
                8'd21: class_label = "BEAR            ";
                8'd22: class_label = "ZEBRA           ";
                8'd23: class_label = "GIRAFFE         ";
                8'd24: class_label = "BACKPACK        ";
                8'd25: class_label = "UMBRELLA        ";
                8'd26: class_label = "HANDBAG         ";
                8'd27: class_label = "TIE             ";
                8'd28: class_label = "SUITCASE        ";
                8'd29: class_label = "FRISBEE         ";
                8'd30: class_label = "SKIS            ";
                8'd31: class_label = "SNOWBOARD       ";
                8'd32: class_label = "SPORTS BALL     ";
                8'd33: class_label = "KITE            ";
                8'd34: class_label = "BASEBALL BAT    ";
                8'd35: class_label = "BASEBALL GLOVE  ";
                8'd36: class_label = "SKATEBOARD      ";
                8'd37: class_label = "SURFBOARD       ";
                8'd38: class_label = "TENNIS RACKET   ";
                8'd39: class_label = "BOTTLE          ";
                8'd40: class_label = "WINE GLASS      ";
                8'd41: class_label = "CUP             ";
                8'd42: class_label = "FORK            ";
                8'd43: class_label = "KNIFE           ";
                8'd44: class_label = "SPOON           ";
                8'd45: class_label = "BOWL            ";
                8'd46: class_label = "BANANA          ";
                8'd47: class_label = "APPLE           ";
                8'd48: class_label = "SANDWICH        ";
                8'd49: class_label = "ORANGE          ";
                8'd50: class_label = "BROCCOLI        ";
                8'd51: class_label = "CARROT          ";
                8'd52: class_label = "HOT DOG         ";
                8'd53: class_label = "PIZZA           ";
                8'd54: class_label = "DONUT           ";
                8'd55: class_label = "CAKE            ";
                8'd56: class_label = "CHAIR           ";
                8'd57: class_label = "SOFA            ";
                8'd58: class_label = "POTTEDPLANT     ";
                8'd59: class_label = "BED             ";
                8'd60: class_label = "DININGTABLE     ";
                8'd61: class_label = "TOILET          ";
                8'd62: class_label = "TVMONITOR       ";
                8'd63: class_label = "LAPTOP          ";
                8'd64: class_label = "MOUSE           ";
                8'd65: class_label = "REMOTE          ";
                8'd66: class_label = "KEYBOARD        ";
                8'd67: class_label = "CELL PHONE      ";
                8'd68: class_label = "MICROWAVE       ";
                8'd69: class_label = "OVEN            ";
                8'd70: class_label = "TOASTER         ";
                8'd71: class_label = "SINK            ";
                8'd72: class_label = "REFRIGERATOR    ";
                8'd73: class_label = "BOOK            ";
                8'd74: class_label = "CLOCK           ";
                8'd75: class_label = "VASE            ";
                8'd76: class_label = "SCISSORS        ";
                8'd77: class_label = "TEDDY BEAR      ";
                8'd78: class_label = "HAIR DRIER      ";
                8'd79: class_label = "TOOTHBRUSH      ";
                default: class_label = "UNKNOWN CLASS   ";
            endcase
        end
    endfunction

    function [7:0] hex_char;
        input [3:0] value;
        begin hex_char=value<10?(8'd48+value):(8'd65+value-10);end
    endfunction
    function [303:0] static_line;
        input [5:0] rr;
        input [2:0] pp;
        begin
            static_line="                                      ";
            case(rr)
                 0: static_line="ARGONAUTICA                           ";
                 2: static_line="RISC-V FPGA OBJECT DETECTION          ";
                 4: case(pp)
                     0:static_line="STATE    : WAITING FOR INPUT          ";
                     1:static_line="STATE    : CAPTURING HDMI             ";
                     2:static_line="STATE    : RUNNING INFERENCE          ";
                     3:static_line="STATE    : COMPLETE                   ";
                     default:static_line="STATE    : ERROR                      ";
                    endcase
                 6: static_line="SOURCE   : HDMI IN / 1080P60          ";
                 8: static_line="RESULTS SHOWN :                       ";
                 9: static_line="FORWARD  : 0000.000 S                 ";
                11: static_line="NO.  OBJECT                CONFIDENCE ";
                24: static_line="TOP 10 NMS RESULTS / FPGA INFERENCE   ";
                26: static_line="HDMI RESULT PAGE /                    ";
                default:static_line="                                      ";
            endcase
        end
    endfunction

    reg [7:0] ch;
    reg [303:0] line_text;
    reg [127:0] label_text;
    reg [7:0] item_class;
    reg [9:0] item_score;
    reg [3:0] item_index;
    reg [15:0] score_bcd,score_adjust;
    reg [9:0] score_shift;
    reg [34:0] bits;
    reg ink;
    reg [23:0] color;
    integer k,n;
    always @* begin
        line_text=static_line(row,shown_phase);
        ch=8'd32;label_text=0;item_class=0;item_score=0;item_index=0;
        score_bcd=0;score_adjust=0;score_shift=0;
        if(col<38)ch=line_text[(37-col)*8+:8];
        if(row==8&&col>=16&&col<=18)begin
            if(!valid_frame)ch=8'd45;
            else case(col)
                16:ch=8'd48+(count_frame/100);
                17:ch=8'd48+((count_frame/10)%10);
                default:ch=8'd48+(count_frame%10);
            endcase
        end
        if(row==9&&col>=11&&col<=18)begin
            if(!valid_frame||shown_phase!=3)ch=8'd45;
            else if(ms_frame>32'd9999999)begin
                case(col)
                    11:ch="O";12:ch="V";13:ch="E";14:ch="R";
                    15:ch="F";16:ch="L";17:ch="O";18:ch="W";
                endcase
            end else case(col)
                11:ch=8'd48+time_bcd[27:24];
                12:ch=8'd48+time_bcd[23:20];
                13:ch=8'd48+time_bcd[19:16];
                14:ch=8'd48+time_bcd[15:12];
                15:ch=".";
                16:ch=8'd48+time_bcd[11:8];
                17:ch=8'd48+time_bcd[7:4];
                18:ch=8'd48+time_bcd[3:0];
            endcase
        end
        if(row>=12&&row<22)begin
            item_index=row-12;
            if(valid_frame&&shown_phase==3&&item_index<count_frame)begin
                item_class=classes_frame[8*item_index+:8];
                item_score=scores_frame[10*item_index+:10];
                if(item_score>1000)item_score=1000;
                label_text=class_label(item_class);
                score_shift=item_score;
                // Only a bounded ten-bit score conversion is combinational.
                for(k=0;k<10;k=k+1)begin
                    score_adjust=score_bcd;
                    for(n=0;n<4;n=n+1)
                        if(score_bcd[4*n+:4]>=5)
                            score_adjust[4*n+:4]=score_bcd[4*n+:4]+4'd3;
                    score_bcd={score_adjust[14:0],score_shift[9]};
                    score_shift={score_shift[8:0],1'b0};
                end
                if(col==0)ch=item_index==9?"1":" ";
                else if(col==1)ch=8'd48+((item_index+1)%10);
                else if(col==2)ch=".";
                else if(col>=5&&col<21)ch=label_text[(20-col)*8+:8];
                else if(col==27)ch=score_bcd[15:12]==0?" ":8'd48+score_bcd[15:12];
                else if(col==28)ch=8'd48+score_bcd[11:8];
                else if(col==29)ch=8'd48+score_bcd[7:4];
                else if(col==30)ch=".";
                else if(col==31)ch=8'd48+score_bcd[3:0];
                else if(col==32)ch="%";
            end else if(row==12&&valid_frame&&shown_phase==3&&count_frame==0)begin
                line_text="NO DETECTIONS                         ";
                if(col<38)ch=line_text[(37-col)*8+:8];
            end
        end
        if(row==23&&valid_frame&&count_frame>10)begin
            line_text="FIRST TEN DETECTIONS SHOWN            ";
            if(col<38)ch=line_text[(37-col)*8+:8];
        end
        if(row==26&&col>=19&&col<38)begin
            line_text=valid_frame?"                   BOARD RESULTS      ":"                   LEGACY CODE 00     ";
            ch=line_text[(37-col)*8+:8];
            if(!valid_frame&&col==31)ch=hex_char(code_frame[7:4]);
            if(!valid_frame&&col==32)ch=hex_char(code_frame[3:0]);
        end
        bits=glyph(ch);
        ink=text_area&&gx<5&&gy<7&&bits[34-(gy*5+gx)];
        color=24'h0b1420;
        if(y>=16&&y<80)color=24'h132a41;
        if(y>=80&&y<112)begin
            if(shown_phase>=4)color=24'h602735;
            else if(shown_phase==3)color=24'h164d3b;
            else color=24'h163953;
        end
        if(y>=192&&y<368&&row[0])color=24'h111f30;
        if(y==190||y==368)color=24'h31536b;
        if(x==15||x==624)color=24'h182c40;
        if(ink)begin
            if(row==0)color=24'h72dfc1;
            else if(row==11||row==24||row==26)color=24'h83b8d0;
            else if(row>=12&&row<22&&col>=27)color=24'h72dfc1;
            else color=24'he8f2fb;
        end
    end

    always @(posedge pix_clk or negedge rst_n)begin
        if(!rst_n)begin
            h<=0;v<=0;code_meta<=0;code_sync<=0;code_frame<=0;
            valid_frame<=0;phase_frame<=0;count_frame<=0;ms_frame<=0;
            classes_frame<=0;scores_frame<=0;
            hs<=1;vs<=1;de<=0;r<=0;g<=0;b<=0;
        end else begin
            code_meta<=status_code;code_sync<=code_meta;
            if(frame_start)begin
                code_frame<=code_sync;valid_frame<=result_valid;
                phase_frame<=phase;count_frame<=count;ms_frame<=forward_ms;
                classes_frame<=classes;scores_frame<=scores;
            end
            if(pixel_enable)begin
                if(h==799)begin h<=0;if(v==524)v<=0;else v<=v+1'b1;end
                else h<=h+1'b1;
                hs<=!(h<96);vs<=!(v<2);de<=active;
                if(active)begin r<=color[23:16];g<=color[15:8];b<=color[7:0];end
                else begin r<=0;g<=0;b<=0;end
            end
        end
    end
endmodule
