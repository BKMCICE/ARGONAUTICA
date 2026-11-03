// A48 isolated optional eight-output postprocessor. A02 raw MAC/RAM/registers are reused.
// Packed bytes are output-major, ceil(pixels/4) words per output, zero tail.
module ai_conv3x3_quant8 #(parameter LATCH_SHAPE_VALID=0) (
    input wire clk,rst_n,req,we,
    input wire [3:0] be,
    input wire [31:0] addr,wdata,
    output reg [31:0] rdata,
    output wire ready
);
    localparam IDLE=0,WAIT_MAC=1,CHECK_MAC=2,SET_ADDR=3,FETCH=4,
        START_Q=5,WAIT_Q=6,STORE=7,RESET_ADDR=8,COMMIT=9;
    wire cap=addr[11:2]==10'h00b;
    wire qreg=addr[11:8]==4'h2;
    reg enabled,leaky,error,done,valid;
    reg [3:0] state;
    reg [31:0] shape;
    wire [3:0] cfg_pixels=shape[3:0],cfg_outputs=shape[7:4],cfg_last=shape[19:16];
    wire [5:0] cfg_blocks=shape[13:8];
    wire combinational_shape_valid=(shape&32'hfff0c000)==0 && cfg_pixels>=1 && cfg_pixels<=8 &&
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
    wire [8:0] wanted_mask=(9'd1<<cfg_outputs)-1;
    reg signed [31:0] multipliers[0:7],biases[0:7];
    reg [7:0] mult_valid,bias_valid;
    wire params_valid=(mult_valid&wanted_mask[7:0])==wanted_mask[7:0] &&
        (bias_valid&wanted_mask[7:0])==wanted_mask[7:0];
    reg [3:0] param_addr,output_index;
    reg [3:0] pixels,outputs,pixel_index;
    reg [4:0] packed_write,packed_read,packed_count;
    reg [31:0] packed_words[0:15],packed_work;
    reg [31:0] post_cycles,post_items;
    reg signed [31:0] held_acc;
    reg [7:0] held_byte;
    wire core_busy;
    wire busy=core_busy || state!=IDLE;
    wire block_start=req && we && addr[11:0]==12'h104 && wdata[0];
    wire admissible=state==IDLE && !core_busy && shape_valid && params_valid;
    reg core_req,core_we;
    reg [3:0] core_be;
    reg [31:0] core_addr,core_wdata;
    wire [31:0] core_rdata;
    wire quant_busy,quant_done,quant_error;
    wire signed [7:0] quant_value;
    wire [31:0] next_packed=(pixel_index[1:0]==0 ? 32'b0 : packed_work) |
        ({24'b0,held_byte} << {pixel_index[1:0],3'b0});
    assign ready=1'b1;
    ai_conv3x3_block8 #(.LATCH_SHAPE_VALID(LATCH_SHAPE_VALID)) core(.clk(clk),.rst_n(rst_n),.req(core_req),.we(core_we),
        .be(core_be),.addr(core_addr),.wdata(core_wdata),.rdata(core_rdata),.ready(),.busy(core_busy));
    ai_q24_post post(.clk(clk),.rst_n(rst_n),.start(state==START_Q),.acc(held_acc),
        .mult(multipliers[output_index[2:0]]),.bias(biases[output_index[2:0]]),.leaky(leaky),
        .busy(quant_busy),.done(quant_done),.error(quant_error),.value(quant_value));
    always @(*) begin
        core_req=req && !cap && !qreg && state==IDLE;
        if(enabled && block_start && !admissible)core_req=0;
        core_we=we;core_be=be;core_addr=addr;core_wdata=wdata;
        case(state)
            CHECK_MAC:begin core_req=1;core_we=0;core_addr='h104;end
            SET_ADDR,RESET_ADDR:begin core_req=1;core_we=1;core_be=15;core_addr='h11c;core_wdata=0;end
            FETCH:begin core_req=1;core_we=0;core_addr='h120;end
            default:;
        endcase
    end
    always @(*) begin
        rdata=state==IDLE ? core_rdata : 0;
        if(state!=IDLE && addr[11:8]==0 && addr[5:2]==0)rdata=1;
        if(addr[11:0]=='h104 && enabled)rdata={29'b0,(error | (state==IDLE && core_rdata[2])),done,busy};
        if(cap)rdata=addr[1:0]==0 ? 32'h41343831 : 0;
        if(qreg)begin
            rdata=0;
            if(addr[1:0]==0)case(addr[11:0])
                'h200:rdata={8'b0,bias_valid,mult_valid,4'b0,valid,error,done,busy};
                'h204:rdata={30'b0,leaky,enabled};
                'h208:rdata={28'b0,param_addr};
                'h20c:if(param_addr<8 && mult_valid[param_addr[2:0]])rdata=multipliers[param_addr[2:0]];
                'h210:if(param_addr<8 && bias_valid[param_addr[2:0]])rdata=biases[param_addr[2:0]];
                'h21c:rdata={27'b0,packed_read};
                'h220:if(!busy && valid && packed_read<packed_count)rdata=packed_words[packed_read[3:0]];
                'h224:rdata={27'b0,packed_count};
                'h228:rdata=post_cycles;
                'h22c:rdata=post_items;
                default:;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;enabled<=0;leaky<=0;error<=0;done<=0;valid<=0;shape<=0;shape_valid_q<=0;
            mult_valid<=0;bias_valid<=0;param_addr<=0;output_index<=0;
            pixels<=0;outputs<=0;pixel_index<=0;packed_write<=0;packed_read<=0;packed_count<=0;
            packed_work<=0;held_acc<=0;held_byte<=0;post_cycles<=0;post_items<=0;
            // Parameter and packed payload registers are guarded by validity.
        end else begin
            if(state>=CHECK_MAC)post_cycles<=post_cycles+1;
            case(state)
                WAIT_MAC:if(!core_busy)state<=CHECK_MAC;
                CHECK_MAC:begin
                    if(core_rdata[2:1]!=2'b01)begin error<=1;done<=1;valid<=0;state<=IDLE;end
                    else state<=SET_ADDR;
                end
                SET_ADDR:state<=FETCH;
                FETCH:begin held_acc<=core_rdata;state<=START_Q;end
                START_Q:begin post_items<=post_items+1;state<=WAIT_Q;end
                WAIT_Q:if(quant_done)begin
                    if(quant_error)begin error<=1;done<=1;valid<=0;state<=IDLE;end
                    else begin held_byte<=quant_value;state<=STORE;end
                end
                STORE:begin
                    packed_work<=next_packed;
                    if(pixel_index[1:0]==3 || pixel_index==pixels-1)begin
                        packed_write<=packed_write+1;packed_work<=0;
                    end
                    if(pixel_index==pixels-1)begin
                        pixel_index<=0;output_index<=output_index+1;
                        if(output_index==outputs-1)state<=RESET_ADDR;else state<=FETCH;
                    end else begin pixel_index<=pixel_index+1;state<=FETCH;end
                end
                RESET_ADDR:state<=COMMIT;
                COMMIT:begin done<=1;valid<=!error;packed_count<=packed_write;packed_read<=0;state<=IDLE;end
                default:;
            endcase
            if(req && (cap || qreg))begin
                if(addr[1:0]!=0 || (we && be!=15))begin error<=1;valid<=0;end
                else if(cap)begin if(we)begin error<=1;valid<=0;end end
                else if(we)begin
                    if(busy)begin error<=1;valid<=0;end
                    else case(addr[11:0])
                        'h200:if(wdata==4)begin done<=0;error<=0;valid<=0;end else begin error<=1;valid<=0;end
                        'h204:begin
                            if(wdata[31:2]!=0)error<=1;
                            else begin enabled<=wdata[0];leaky<=wdata[1];error<=0;done<=0;end
                            mult_valid<=0;bias_valid<=0;valid<=0;packed_count<=0;
                        end
                        'h208:begin
                            if(wdata<8)begin param_addr<=wdata[3:0];mult_valid<=0;bias_valid<=0;end
                            else error<=1;
                            valid<=0;
                        end
                        'h20c:begin
                            if(param_addr<8)begin mult_valid[param_addr[2:0]]<=1;bias_valid[param_addr[2:0]]<=0;end
                            else error<=1;
                            valid<=0;
                        end
                        'h210:begin
                            if(param_addr<8 && mult_valid[param_addr[2:0]])begin bias_valid[param_addr[2:0]]<=1;param_addr<=param_addr+1;end
                            else error<=1;
                            valid<=0;
                        end
                        'h21c:if(wdata<16)packed_read<=wdata[4:0];else begin error<=1;valid<=0;end
                        default:begin error<=1;valid<=0;end
                    endcase
                end else if(addr[11:0]=='h220)begin
                    if(busy || !valid || packed_read>=packed_count)begin error<=1;valid<=0;end
                    else packed_read<=packed_read+1;
                end else case(addr[11:0])
                    'h200,'h204,'h208,'h20c,'h210,'h21c,'h224,'h228,'h22c:;
                    default:begin error<=1;valid<=0;end
                endcase
            end
            if(req && we && !cap && !qreg)begin
                if(state!=IDLE)begin error<=1;valid<=0;end
                else if(!core_busy && addr[1:0]==0 && be==15)begin
                    if(addr[11:0]=='h108)begin shape<=wdata;shape_valid_q<=valid_shape(wdata);valid<=0;end
                    if(addr[11:0]=='h104)begin
                        if(wdata[2])begin error<=0;done<=0;valid<=0;end
                        if(wdata[0] && enabled)begin
                            error<=0;done<=0;valid<=0;post_cycles<=0;post_items<=0;packed_count<=0;
                            if(!admissible)begin error<=1;done<=1;end
                            else begin
                                pixels<=cfg_pixels;outputs<=cfg_outputs;pixel_index<=0;output_index<=0;
                                packed_write<=0;packed_read<=0;packed_work<=0;state<=WAIT_MAC;
                            end
                        end
                    end
                end else if(enabled)begin error<=1;valid<=0;end
            end
            if(req && !we && state!=IDLE && addr[11:0]=='h120)begin error<=1;valid<=0;end
        end
    end
    always @(posedge clk)if(rst_n)begin
        if(state==STORE && (pixel_index[1:0]==3 || pixel_index==pixels-1))packed_words[packed_write[3:0]]<=next_packed;
        if(req && we && qreg && addr[1:0]==0 && be==15 && !busy && param_addr<8)begin
            if(addr[11:0]=='h20c)multipliers[param_addr[2:0]]<=wdata;
            if(addr[11:0]=='h210 && mult_valid[param_addr[2:0]])biases[param_addr[2:0]]<=wdata;
        end
    end
endmodule
