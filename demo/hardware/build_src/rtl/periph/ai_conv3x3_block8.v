// Generated A33: A02 semantics, eight outputs, capability A331 at 0x28.
module ai_conv3x3_block8 #(parameter LATCH_SHAPE_VALID=0) (
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
    reg [71:0] weights [0:199];
    reg [31:0] results [0:63];
    reg [199:0] pixel_valid;
    reg [199:0] weight_valid;
    reg [7:0] p_upload;
    reg [7:0] w_upload;
    reg [1:0] p_word,w_word;
    reg [6:0] r_read;
    reg [31:0] shape;
    wire [3:0] cfg_pixels=shape[3:0], cfg_outputs=shape[7:4];
    wire [5:0] cfg_blocks=shape[13:8];
    wire [3:0] cfg_last=shape[19:16];
    wire combinational_shape_valid=(shape & 32'hfff0c000)==0 && cfg_pixels>=1 && cfg_pixels<=8 &&
        cfg_outputs>=1 && cfg_outputs<=8 && cfg_blocks>=1 && cfg_blocks<=25 &&
        cfg_last>=1 && cfg_last<=9 && !(cfg_blocks==25 && cfg_last==9);
    function valid_shape;
        input [31:0] value;
        begin valid_shape=(value & 32'hfff0c000)==0 && value[3:0]>=1 && value[3:0]<=8 &&
            value[7:4]>=1 && value[7:4]<=8 && value[13:8]>=1 && value[13:8]<=25 &&
            value[19:16]>=1 && value[19:16]<=9 && !(value[13:8]==25 && value[19:16]==9);end
    endfunction
    reg shape_valid_q;
    wire shape_valid=LATCH_SHAPE_VALID ? shape_valid_q : combinational_shape_valid;
    reg [3:0] n_pixels,n_outputs,last_lanes;
    reg [5:0] n_blocks;
    reg [3:0] out_index,pixel_index;
    reg [5:0] block_index;
    reg [6:0] r_write,result_count;
    reg [7:0] p_index;
    reg [7:0] w_index,w_base;
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
            shape<=0;shape_valid_q<=0;pixel_valid<=0;weight_valid<=0;p_upload<=0;w_upload<=0;
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
                        // Same acceptance edge as shape, including all of the
                        // existing alignment/byte-enable/busy guards above.
                        12'h108:begin shape<=wdata;shape_valid_q<=valid_shape(wdata);end
                        12'h10c:if(wdata<200) begin w_upload<=wdata[7:0];w_word<=0;end else tile_error<=1;
                        12'h110:if(w_upload<200) begin
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
                        12'h11c:if(wdata<64) r_read<=wdata[6:0];else tile_error<=1;
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
            if(tile_state==ADD && block_index==n_blocks-1) results[r_write[5:0]]<=next_partial;
            if(req && we && !legacy_region && addr[1:0]==0 && be==4'hf && !exclusive_busy) begin
                if(addr[11:0]==12'h110 && w_upload<200) case(w_word)
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
        if(addr[11:0]==12'h028) rdata=32'h41333331;
        else if(legacy_region) case(addr[5:2])
            0:rdata={30'b0,legacy_done,exclusive_busy};
            1:rdata=pix0;2:rdata=pix1;3:rdata=pix2;4:rdata=wgt0;5:rdata=wgt1;6:rdata=wgt2;
            7:rdata=bias;8:rdata={{24{result[7]}},result};9:rdata=accum;default:;
        endcase
        else if(addr[1:0]==0) case(addr[11:0])
            12'h100:rdata=32'h41303131;
            12'h104:rdata={29'b0,tile_error,tile_done,exclusive_busy};
            12'h108:rdata=shape;12'h10c:rdata={24'b0,w_upload};12'h114:rdata={24'b0,p_upload};
            12'h11c:rdata={25'b0,r_read};
            12'h120:if(!tile_busy && results_valid && r_read<result_count) rdata=results[r_read[5:0]];
            12'h124:rdata=tile_cycles;12'h128:rdata=tile_dots;default:;
        endcase
    end
endmodule
