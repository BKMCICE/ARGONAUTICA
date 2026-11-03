// Optional A01 block engine; default elaboration retains the original primitive.
module ai_conv3x3 #(parameter ENABLE_BLOCK = 0, parameter ENABLE_WINDOW = 0, parameter ENABLE_QUANT = 0, parameter ENABLE_BLOCK8 = 0, parameter LATCH_SHAPE_VALID = 0) (
    input wire clk, rst_n, req, we,
    input wire [3:0] be,
    input wire [31:0] addr, wdata,
    output wire [31:0] rdata,
    output wire ready
);
    generate if (ENABLE_BLOCK == 0 && ENABLE_WINDOW == 0 && ENABLE_QUANT == 0 && ENABLE_BLOCK8 == 0) begin: legacy
        ai_conv3x3_legacy u_impl (.clk(clk),.rst_n(rst_n),.req(req),.we(we),
            .be(be),.addr(addr),.wdata(wdata),.rdata(rdata),.ready(ready));
    end else if (ENABLE_BLOCK == 1 && ENABLE_WINDOW == 0 && ENABLE_QUANT == 0 && ENABLE_BLOCK8 == 0) begin: block_engine
        ai_conv3x3_block u_impl (.clk(clk),.rst_n(rst_n),.req(req),.we(we),
            .be(be),.addr(addr),.wdata(wdata),.rdata(rdata),.ready(ready));
    end else if (ENABLE_BLOCK == 1 && ENABLE_WINDOW == 1 && ENABLE_QUANT == 0 && ENABLE_BLOCK8 == 0) begin: window_engine
        ai_conv3x3_window u_impl (.clk(clk),.rst_n(rst_n),.req(req),.we(we),
            .be(be),.addr(addr),.wdata(wdata),.rdata(rdata),.ready(ready));
    end else if (ENABLE_BLOCK == 1 && ENABLE_WINDOW == 0 && ENABLE_QUANT == 1 && ENABLE_BLOCK8 == 0) begin: quant_engine
        ai_conv3x3_quant u_impl (.clk(clk),.rst_n(rst_n),.req(req),.we(we),
            .be(be),.addr(addr),.wdata(wdata),.rdata(rdata),.ready(ready));
    end else if (ENABLE_BLOCK == 1 && ENABLE_WINDOW == 0 && ENABLE_QUANT == 0 && ENABLE_BLOCK8 == 1) begin: block8_engine
        ai_conv3x3_block8 #(.LATCH_SHAPE_VALID(LATCH_SHAPE_VALID)) u_impl (.clk(clk),.rst_n(rst_n),.req(req),.we(we),
            .be(be),.addr(addr),.wdata(wdata),.rdata(rdata),.ready(ready));
    end else if (ENABLE_BLOCK == 1 && ENABLE_WINDOW == 0 && ENABLE_QUANT == 1 && ENABLE_BLOCK8 == 1) begin: block8_quant_engine
        // A48 isolated composition: A331 raw8 plus A481 post8 at0x2c.
        // Neither the formal raw8 elaboration nor the old quant4 branch changes.
        ai_conv3x3_quant8 #(.LATCH_SHAPE_VALID(LATCH_SHAPE_VALID)) u_impl (.clk(clk),.rst_n(rst_n),.req(req),.we(we),
            .be(be),.addr(addr),.wdata(wdata),.rdata(rdata),.ready(ready));
    end else begin: invalid_configuration
        initial $fatal(1,"Optional AI modes require block=1, binary flags and exclusive window mode");
        assign rdata=0;assign ready=0;
    end endgenerate
endmodule

// Nine-lane signed INT8 3x3 convolution primitive for the edge-AI path.
// CPU writes pixels/weights, bias, then CTRL; result is requantized to INT8.
// 0x00 CTRL: write bit0=start, bit1=ReLU, bits12:8=right shift;
//             read bit0=busy, bit1=done (write-1 to bit2 clears done)
// 0x04/08/0C PIX[0:3]/[4:7]/[8]
// 0x10/14/18 WGT[0:3]/[4:7]/[8]
// 0x1C BIAS (signed 32-bit); 0x20 RESULT (sign-extended INT8)
// 0x24 ACCUM (raw signed 32-bit dot product + bias; valid when done)
module ai_conv3x3_legacy (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready
);
    assign ready = 1'b1;
    reg [31:0] pix0, pix1, pix2, wgt0, wgt1, wgt2, bias;
    reg [1:0] state;
    reg done, relu;
    reg [4:0] shift;
    reg signed [15:0] product [0:8];
    reg signed [31:0] accum;
    reg signed [7:0] result;
    wire [71:0] pixels = {pix2[7:0], pix1, pix0};
    wire [71:0] weights = {wgt2[7:0], wgt1, wgt0};
    integer i, j;
    reg signed [31:0] sum;
    reg signed [31:0] scaled;

    always @(*) begin
        sum = $signed(bias);
        for (j = 0; j < 9; j = j + 1)
            sum = sum + $signed(product[j]);
        scaled = accum >>> shift;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pix0 <= 0; pix1 <= 0; pix2 <= 0;
            wgt0 <= 0; wgt1 <= 0; wgt2 <= 0;
            bias <= 0; state <= 0; done <= 0;
            relu <= 0; shift <= 0; accum <= 0; result <= 0;
            for (i = 0; i < 9; i = i + 1) product[i] <= 0;
        end else begin
            if (req && we) begin
                case (addr[5:2])
                    4'd0: begin
                        if (wdata[2]) done <= 0;
                        if (wdata[0] && state == 0) begin
                            relu <= wdata[1];
                            shift <= wdata[12:8];
                            for (i = 0; i < 9; i = i + 1)
                                product[i] <= $signed(pixels[i*8 +: 8]) * $signed(weights[i*8 +: 8]);
                            done <= 0;
                            state <= 1;
                        end
                    end
                    4'd1: pix0 <= wdata;
                    4'd2: pix1 <= wdata;
                    4'd3: pix2 <= wdata;
                    4'd4: wgt0 <= wdata;
                    4'd5: wgt1 <= wdata;
                    4'd6: wgt2 <= wdata;
                    4'd7: bias <= wdata;
                    default: ;
                endcase
            end
            if (state == 1) begin
                accum <= sum;
                state <= 2;
            end else if (state == 2) begin
                if (relu && scaled < 0) result <= 0;
                else if (scaled > 127) result <= 8'sd127;
                else if (scaled < -128) result <= -8'sd128;
                else result <= scaled[7:0];
                done <= 1;
                state <= 0;
            end
        end
    end
    always @(*) begin
        case (addr[5:2])
            4'd0: rdata = {30'b0, done, state != 0};
            4'd1: rdata = pix0;
            4'd2: rdata = pix1;
            4'd3: rdata = pix2;
            4'd4: rdata = wgt0;
            4'd5: rdata = wgt1;
            4'd6: rdata = wgt2;
            4'd7: rdata = bias;
            4'd8: rdata = {{24{result[7]}}, result};
            4'd9: rdata = accum;
            default: rdata = 0;
        endcase
    end
endmodule

// A01: compact [output][block] weights, [block][pixel] inputs, [output][pixel]
// int32 results. One nine-multiplier bank shared with the legacy instruction.
// No DDR master, quantizer, interrupt, or concurrent legacy/block ownership.
module ai_conv3x3_block (
    input wire clk, rst_n, req, we,
    input wire [3:0] be,
    input wire [31:0] addr, wdata,
    output reg [31:0] rdata,
    output wire ready,
    output wire busy
);
    localparam IDLE=2'd0, LOAD=2'd1, MULT=2'd2, ADD=2'd3;
    reg [31:0] pix0,pix1,pix2,wgt0,wgt1,wgt2,bias;
    reg [1:0] legacy_state, tile_state;
    reg legacy_done,relu;
    reg [4:0] shift;
    reg signed [15:0] product [0:8];
    reg signed [31:0] accum;
    reg signed [7:0] result;
    reg signed [31:0] sum_products;
    wire signed [31:0] legacy_sum=$signed(bias)+sum_products;
    wire signed [31:0] scaled=accum >>> shift;
    wire [71:0] legacy_pixels={pix2[7:0],pix1,pix0};
    wire [71:0] legacy_weights={wgt2[7:0],wgt1,wgt0};
    reg [71:0] pixels [0:199];
    reg [71:0] weights [0:99];
    reg [31:0] results [0:31];
    reg [199:0] pixel_valid;
    reg [99:0] weight_valid;
    reg [7:0] p_upload;
    reg [6:0] w_upload;
    reg [1:0] p_word,w_word;
    reg [5:0] r_read;
    reg [31:0] shape;
    wire [3:0] cfg_pixels=shape[3:0], cfg_outputs=shape[7:4];
    wire [5:0] cfg_blocks=shape[13:8];
    wire [3:0] cfg_last=shape[19:16];
    wire shape_valid=(shape & 32'hfff0c000)==0 && cfg_pixels>=1 && cfg_pixels<=8 &&
        cfg_outputs>=1 && cfg_outputs<=4 && cfg_blocks>=1 && cfg_blocks<=25 &&
        cfg_last>=1 && cfg_last<=9 && !(cfg_blocks==25 && cfg_last==9);
    reg [3:0] n_pixels,n_outputs,last_lanes;
    reg [5:0] n_blocks;
    reg [3:0] out_index,pixel_index;
    reg [5:0] block_index,r_write,result_count;
    reg [7:0] p_index;
    reg [6:0] w_index,w_base;
    reg [71:0] held_pixels,held_weights;
    reg signed [31:0] partial;
    reg tile_done,tile_error,results_valid;
    reg [31:0] tile_cycles,tile_dots;
    wire tile_busy=tile_state!=IDLE;
    wire exclusive_busy=tile_busy || legacy_state!=0;
    assign busy=exclusive_busy;
    wire legacy_region=addr[11:8]==0;
    wire legacy_start=req && we && legacy_region && addr[5:2]==0 && wdata[0] && !exclusive_busy;
    wire [71:0] selected_pixels=tile_busy ? held_pixels : legacy_pixels;
    wire [71:0] selected_weights=tile_busy ? held_weights : legacy_weights;
    wire signed [31:0] next_partial=partial+sum_products;
    assign ready=1'b1;
    integer i,j;
    always @(*) begin
        sum_products=0;
        for(j=0;j<9;j=j+1) sum_products=sum_products+$signed({{16{product[j][15]}},product[j]});
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pix0<=0;pix1<=0;pix2<=0;wgt0<=0;wgt1<=0;wgt2<=0;bias<=0;
            legacy_state<=0;legacy_done<=0;relu<=0;shift<=0;accum<=0;result<=0;
            tile_state<=IDLE;tile_done<=0;tile_error<=0;results_valid<=0;
            shape<=0;pixel_valid<=0;weight_valid<=0;p_upload<=0;w_upload<=0;
            p_word<=0;w_word<=0;r_read<=0;r_write<=0;result_count<=0;
            n_pixels<=0;n_outputs<=0;n_blocks<=0;last_lanes<=0;
            out_index<=0;pixel_index<=0;block_index<=0;p_index<=0;w_index<=0;w_base<=0;
            partial<=0;tile_cycles<=0;tile_dots<=0;
            for(i=0;i<9;i=i+1) product[i]<=0;
            // Payload RAM is deliberately not reset; validity bits guard reads.
        end else begin
            if(tile_busy) tile_cycles<=tile_cycles+1;
            if(legacy_start || tile_state==MULT) begin
                for(i=0;i<9;i=i+1) begin
                    if(tile_busy && block_index==n_blocks-1 && i>=last_lanes) product[i]<=0;
                    else product[i]<=$signed(selected_pixels[i*8 +: 8])*$signed(selected_weights[i*8 +: 8]);
                end
            end
            if(req && legacy_region && we) begin
                if(tile_busy) tile_error<=1;
                else case(addr[5:2])
                    0: begin
                        if(wdata[2]) legacy_done<=0;
                        if(legacy_start) begin
                            relu<=wdata[1];shift<=wdata[12:8];legacy_done<=0;legacy_state<=1;
                        end
                    end
                    1:pix0<=wdata;2:pix1<=wdata;3:pix2<=wdata;
                    4:wgt0<=wdata;5:wgt1<=wdata;6:wgt2<=wdata;7:bias<=wdata;
                    default:;
                endcase
            end
            if(legacy_state==1) begin accum<=legacy_sum;legacy_state<=2;end
            else if(legacy_state==2) begin
                if(relu && scaled<0) result<=0;
                else if(scaled>127) result<=8'sd127;
                else if(scaled< -128) result<= -8'sd128;
                else result<=scaled[7:0];
                legacy_done<=1;legacy_state<=0;
            end
            case(tile_state)
                LOAD: begin
                    if(!pixel_valid[p_index] || !weight_valid[w_index]) begin
                        tile_error<=1;tile_done<=1;tile_state<=IDLE;results_valid<=0;
                    end else begin
                        tile_state<=MULT;
                    end
                end
                MULT:begin tile_dots<=tile_dots+1;tile_state<=ADD;end
                ADD:begin
                    if(block_index==n_blocks-1) begin
                        r_write<=r_write+1;partial<=0;block_index<=0;
                        if(pixel_index==n_pixels-1) begin
                            pixel_index<=0;p_index<=0;out_index<=out_index+1;
                            w_base<=w_base+n_blocks;w_index<=w_base+n_blocks;
                            if(out_index==n_outputs-1) begin
                                tile_done<=1;results_valid<=1;result_count<=r_write+1;tile_state<=IDLE;
                            end else tile_state<=LOAD;
                        end else begin
                            pixel_index<=pixel_index+1;p_index<={4'b0,pixel_index}+1;
                            w_index<=w_base;tile_state<=LOAD;
                        end
                    end else begin
                        partial<=next_partial;block_index<=block_index+1;
                        p_index<=p_index+{4'b0,n_pixels};w_index<=w_index+1;tile_state<=LOAD;
                    end
                end
                default:;
            endcase
            if(req && !legacy_region) begin
                if(addr[1:0]!=0 || (we && be!=4'hf)) tile_error<=1;
                else if(we) begin
                    if(exclusive_busy) tile_error<=1;
                    else case(addr[11:0])
                        12'h104: begin
                            if(wdata[2]) begin tile_done<=0;tile_error<=0;results_valid<=0;end
                            if(wdata[0]) begin
                                tile_done<=0;tile_error<=0;results_valid<=0;tile_cycles<=0;tile_dots<=0;
                                if(!shape_valid) begin tile_done<=1;tile_error<=1;end
                                else begin
                                    n_pixels<=cfg_pixels;n_outputs<=cfg_outputs;n_blocks<=cfg_blocks;last_lanes<=cfg_last;
                                    out_index<=0;pixel_index<=0;block_index<=0;r_write<=0;r_read<=0;result_count<=0;
                                    p_index<=0;w_index<=0;w_base<=0;partial<=0;tile_state<=LOAD;
                                end
                            end
                        end
                        12'h108:shape<=wdata;
                        12'h10c:if(wdata<100) begin w_upload<=wdata[6:0];w_word<=0;end else tile_error<=1;
                        12'h110:if(w_upload<100) begin
                            case(w_word)
                                0:weight_valid[w_upload]<=0;
                                1:;
                                2:weight_valid[w_upload]<=1;
                            endcase
                            if(w_word==2) begin w_word<=0;w_upload<=w_upload+1;end else w_word<=w_word+1;
                        end else tile_error<=1;
                        12'h114:if(wdata<200) begin p_upload<=wdata[7:0];p_word<=0;end else tile_error<=1;
                        12'h118:if(p_upload<200) begin
                            case(p_word)
                                0:pixel_valid[p_upload]<=0;
                                1:;
                                2:pixel_valid[p_upload]<=1;
                            endcase
                            if(p_word==2) begin p_word<=0;p_upload<=p_upload+1;end else p_word<=p_word+1;
                        end else tile_error<=1;
                        12'h11c:if(wdata<32) r_read<=wdata[5:0];else tile_error<=1;
                        default:tile_error<=1;
                    endcase
                end else if(addr[11:0]==12'h120) begin
                    if(tile_busy || !results_valid || r_read>=result_count) tile_error<=1;
                    else r_read<=r_read+1;
                end else case(addr[11:0])
                    12'h100,12'h104,12'h108,12'h10c,12'h114,12'h11c,12'h124,12'h128:;
                    default:tile_error<=1;
                endcase
            end
        end
    end
    // Payload RAM has no asynchronous reset. Keep these synchronous ports
    // outside the resettable controller so synthesis can infer actual memories.
    // LOAD captures both operands; MULT consumes them on the following edge.
    always @(posedge clk) begin
        if(rst_n) begin
            if(tile_state==LOAD) begin
                held_pixels<=pixels[p_index];held_weights<=weights[w_index];
            end
            if(tile_state==ADD && block_index==n_blocks-1) results[r_write[4:0]]<=next_partial;
            if(req && we && !legacy_region && addr[1:0]==0 && be==4'hf && !exclusive_busy) begin
                if(addr[11:0]==12'h110 && w_upload<100) case(w_word)
                    0:weights[w_upload][31:0]<=wdata;
                    1:weights[w_upload][63:32]<=wdata;
                    2:weights[w_upload][71:64]<=wdata[7:0];
                    default:;
                endcase
                if(addr[11:0]==12'h118 && p_upload<200) case(p_word)
                    0:pixels[p_upload][31:0]<=wdata;
                    1:pixels[p_upload][63:32]<=wdata;
                    2:pixels[p_upload][71:64]<=wdata[7:0];
                    default:;
                endcase
            end
        end
    end
    always @(*) begin
        rdata=0;
        if(legacy_region) case(addr[5:2])
            0:rdata={30'b0,legacy_done,exclusive_busy};
            1:rdata=pix0;2:rdata=pix1;3:rdata=pix2;4:rdata=wgt0;5:rdata=wgt1;6:rdata=wgt2;
            7:rdata=bias;8:rdata={{24{result[7]}},result};9:rdata=accum;default:;
        endcase
        else if(addr[1:0]==0) case(addr[11:0])
            12'h100:rdata=32'h41303131;
            12'h104:rdata={29'b0,tile_error,tile_done,exclusive_busy};
            12'h108:rdata=shape;12'h10c:rdata={25'b0,w_upload};12'h114:rdata={24'b0,p_upload};
            12'h11c:rdata={26'b0,r_read};
            12'h120:if(!tile_busy && results_valid && r_read<result_count) rdata=results[r_read[4:0]];
            12'h124:rdata=tile_cycles;12'h128:rdata=tile_dots;default:;
        endcase
    end
endmodule
