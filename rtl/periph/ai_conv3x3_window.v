// A31 isolated optional bus adapter. The A02 multiplier/RAM datapath is reused.
// See sw/tests/ai_dw3_window/README.md for the exact register/ownership contract.
module ai_conv3x3_window (
    input wire clk,rst_n,req,we,
    input wire [3:0] be,
    input wire [31:0] addr,wdata,
    output reg [31:0] rdata,
    output wire ready
);
    wire special=addr[11:4]==8'h03;
    wire [1:0] word=addr[3:2];
    reg enabled,error,staged;
    reg [2:0] seeded;
    reg [71:0] window_pixels;
    reg [23:0] column;
    reg [2:0] state;
    wire core_busy;
    wire busy=state!=0 || core_busy;
    wire command=req && we && special && word==2;
    wire valid_command=command && addr[1:0]==0 && be==15 && enabled &&
        !error && !busy && seeded==7 && wdata[30:24]==0 && (!wdata[31] || staged);
    wire [71:0] shifted = wdata[31] ?
        {wdata[23:16],column[23:16],window_pixels[71:64],
         wdata[15:8],column[15:8],window_pixels[47:40],
         wdata[7:0],column[7:0],window_pixels[23:16]} :
        {wdata[23:16],window_pixels[71:56],
         wdata[15:8],window_pixels[47:32],
         wdata[7:0],window_pixels[23:8]};
    reg core_req,core_we;
    reg [3:0] core_be;
    reg [31:0] core_addr,core_wdata;
    wire [31:0] core_rdata;
    assign ready=1'b1;
    ai_conv3x3_block core(.clk(clk),.rst_n(rst_n),.req(core_req),.we(core_we),
        .be(core_be),.addr(core_addr),.wdata(core_wdata),.rdata(core_rdata),
        .ready(),.busy(core_busy));
    always @(*) begin
        core_req=req && !special && state==0;
        core_we=we;core_be=be;core_addr=addr;core_wdata=wdata;
        if(state>=1 && state<=4) begin
            core_req=1;core_we=1;core_be=15;
            case(state)
                1:begin core_addr=4;core_wdata=window_pixels[31:0];end
                2:begin core_addr=8;core_wdata=window_pixels[63:32];end
                3:begin core_addr=12;core_wdata={24'b0,window_pixels[71:64]};end
                default:begin core_addr=0;core_wdata=1;end
            endcase
        end
    end
    always @(*) begin
        rdata=core_rdata;
        // Do not expose internal forwarding address/data during adapter work.
        // Software may only poll CTRL or the new STATUS until it is idle.
        if(state!=0) rdata=0;
        if(addr[11:8]==0 && addr[5:2]==0 && state!=0) rdata=1;
        if(special) begin
            rdata=0;
            if(addr[1:0]==0) case(word)
                0:rdata=32'h41333131; // "A311", safe old-primitive probe reads 0
                1:rdata={27'b0,busy,staged,seeded==7,error,enabled};
                default:;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            enabled<=0;error<=0;staged<=0;seeded<=0;
            window_pixels<=0;column<=0;state<=0;
        end else begin
            if(state!=0) begin
                if(state==5) begin if(!core_busy)state<=0;end
                else state<=state+1;
            end
            if(req && special) begin
                if(addr[1:0]!=0 || (we && be!=15)) begin
                    error<=1;seeded<=0;staged<=0;
                end else if(we) begin
                    if(busy) begin error<=1;seeded<=0;staged<=0;end
                    else case(word)
                        1:begin
                            if(wdata[31:3]!=0 || wdata[1]) error<=1;
                            else begin enabled<=wdata[0];if(wdata[2])error<=0;end
                            seeded<=0;staged<=0;
                        end
                        2:begin
                            if(valid_command) begin window_pixels<=shifted;state<=1;end
                            else begin error<=1;seeded<=0;end
                            staged<=0;
                        end
                        3:begin
                            if(enabled && !error && seeded==7 && wdata[31:24]==0 && !staged) begin
                                column<=wdata[23:0];staged<=1;
                            end else begin error<=1;seeded<=0;staged<=0;end
                        end
                        default:begin error<=1;seeded<=0;staged<=0;end
                    endcase
                end
            end
            if(req && we && !special) begin
                if(busy) begin
                    // Legacy writes retain A02 semantics while its core is busy;
                    // they invalidate sliding ownership. Adapter-busy writes
                    // are suppressed to keep an already accepted task atomic.
                    if(enabled) error<=1;
                    seeded<=0;staged<=0;
                end else if(addr[11:8]==0) begin
                    case(addr[5:2])
                        1:begin window_pixels[31:0]<=wdata;seeded[0]<=1;staged<=0;end
                        2:begin window_pixels[63:32]<=wdata;seeded[1]<=1;staged<=0;end
                        3:begin window_pixels[71:64]<=wdata[7:0];seeded[2]<=1;staged<=0;end
                        4,5,6,7:begin seeded<=0;staged<=0;end
                        0:staged<=0;
                        default:;
                    endcase
                end else begin seeded<=0;staged<=0;end // block ownership switch
            end
        end
    end
endmodule
