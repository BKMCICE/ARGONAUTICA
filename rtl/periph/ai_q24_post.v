// A32 optional postprocessor. Signed32 Q24 plus a bounded unsigned leaky path.
// Half ties round away from zero, then clip to [-127,127].
// Reject values outside the defined int32 software Q24/addition domain.
module ai_q24_post (
    input wire clk,rst_n,start,
    input wire signed [31:0] acc,mult,bias,
    input wire leaky,
    output wire busy,
    output reg done,error,
    output reg signed [7:0] value
);
    localparam IDLE=0,MUL=1,ROUND=2,BIAS=3,DECIDE=4,
        LEAKY_MUL=5,LEAKY_CLIP=6,FINISH=8;
    reg [3:0] state;
    reg signed [31:0] held_acc,held_mult,held_bias;
    reg held_leaky;
    reg signed [63:0] product;
    reg signed [39:0] rounded;
    reg signed [32:0] added;
    reg [10:0] leaky_magnitude;
    reg [31:0] leaky_product;
    wire [7:0] leaky_rounded=leaky_product[31:24]+{7'b0,leaky_product[23]};
    wire [10:0] magnitude_low=(~added[10:0])+11'd1;
    // floor(product/2^24) plus a carry: positive ties increment; negative
    // exact ties retain floor (away from zero), fractions beyond half carry.
    // This is exact for the full signed32 x signed32 product domain.
    wire increment=product[23] && (!product[63] || |product[22:0]);
    wire signed [39:0] rounded_next=$signed(product[63:24])+$signed({39'b0,increment});
    assign busy=state!=IDLE;
    function [7:0] clipped(input signed [39:0] v);
        begin if(v>127)clipped=8'd127;else if(v< -127)clipped=-8'sd127;else clipped=v[7:0];end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;done<=0;error<=0;value<=0;product<=0;
            held_acc<=0;held_mult<=0;held_bias<=0;held_leaky<=0;rounded<=0;added<=0;
            leaky_magnitude<=0;leaky_product<=0;
        end else begin
            done<=0;
            if(state==MUL)product<=held_acc*held_mult;
            if(state==LEAKY_MUL)leaky_product<={21'b0,leaky_magnitude}*32'd1677722;
            case(state)
                IDLE:if(start)begin
                    held_acc<=acc;held_mult<=mult;held_bias<=bias;held_leaky<=leaky;
                    error<=0;value<=0;state<=MUL;
                end
                MUL:state<=ROUND;
                ROUND:begin rounded<=rounded_next;state<=BIAS;end
                BIAS:begin
                    if(rounded< -40'sd2147483647 || rounded>40'sd2147483647)begin
                        error<=1;state<=FINISH;
                    end else begin
                        added<=$signed({rounded[31],rounded[31:0]})+$signed({held_bias[31],held_bias});
                        state<=DECIDE;
                    end
                end
                DECIDE:begin
                    if(added< -33'sd2147483648 || added>33'sd2147483647)begin error<=1;state<=FINISH;end
                    else if(held_leaky && added<0)begin
                        // round(1265*1677722/2^24)=127 and the function is
                        // monotone. Larger magnitudes saturate, including INT_MIN.
                        // For 1..1264 the exact positive product fits 31 bits.
                        if(added<= -33'sd1265)begin value<=-8'sd127;state<=FINISH;end
                        else begin leaky_magnitude<=magnitude_low;state<=LEAKY_MUL;end
                    end
                    else begin value<=clipped({{7{added[32]}},added});state<=FINISH;end
                end
                LEAKY_MUL:state<=LEAKY_CLIP;
                LEAKY_CLIP:begin value<=8'd0-leaky_rounded;state<=FINISH;end
                FINISH:begin done<=1;state<=IDLE;end
                default:begin error<=1;state<=FINISH;end
            endcase
        end
    end
endmodule
