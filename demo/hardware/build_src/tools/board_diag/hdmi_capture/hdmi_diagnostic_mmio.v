// H04J: registered return for NEW frontend diagnostic offsets only.
// Original frame-control0x00..0x1c stays on its existing zero-wait path.
// Accept on one clock, hold data/ready through the next handshake. A master
// may keep req asserted for consecutive transfers; no low-gap is assumed.
module hdmi_diagnostic_mmio(
    input wire clk,rst_n,req,we,input wire [3:0] be,
    input wire [11:0] addr,input wire [31:0] wdata,
    input wire snapshot_busy,snapshot_valid,snapshot_timeout,
    input wire [31:0] snapshot_sequence,input wire [511:0] snapshot_data,
    output wire snapshot_request,ready,output wire [31:0] rdata
);
    reg response=0;
    (* syn_preserve=1 *) reg [31:0] read_result=0;
    reg [31:0] decoded;
    always @*begin
        decoded=32'hdeadbeef;
        case(addr)
            12'h020:decoded=32'h48303449;
            12'h024:decoded={29'b0,snapshot_timeout,snapshot_valid,snapshot_busy};
            12'h028:decoded=snapshot_sequence;
            12'h02c:decoded=0;
            default:if(addr>=12'h030&&addr<=12'h06c&&addr[1:0]==0)
                decoded=snapshot_data[((addr[7:0]-8'h30)>>2)*32+:32];
        endcase
    end
    assign snapshot_request=req&&!response&&we&&be==15&&addr==12'h02c&&wdata==1;
    assign ready=req&&response;
    assign rdata=read_result;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin response<=0;read_result<=0;end
        else if(response)response<=0;
        else if(req)begin response<=1;read_result<=decoded;end
    end
endmodule
