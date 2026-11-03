// H04C isolated transaction mux. All addresses/data are latched; lease changes
// never withdraw/reassign an already presented native DDR line transaction.
module hdmi_frame_line_mux(
    input wire clk,rst_n,dma_lease,
    input wire i_req,input wire [31:0] i_addr,output wire i_ready,
    input wire d_req,d_we,input wire [31:0] d_addr,input wire [255:0] d_wdata,output wire d_ready,
    input wire dma_req,input wire [31:0] dma_addr,input wire [255:0] dma_wdata,output wire dma_ready,
    output wire idle,output wire mem_req,output reg mem_we,
    output reg [31:0] mem_addr,output reg [255:0] mem_wdata,
    input wire mem_ready
);
    wire d_wdata65_holdbuf;
    (* syn_noprune = 1, PAP_DONT_TOUCH = "TRUE" *)
    GTP_LUT1 #(.INIT(2'b10)) u_d_wdata65_holdbuf (
        .I0(d_wdata[65]), .Z(d_wdata65_holdbuf)
    );
    reg active=0;reg [1:0] owner=0;
    assign idle=!active;assign mem_req=active;
    assign i_ready=active&&owner==1&&mem_ready;
    assign d_ready=active&&owner==2&&mem_ready;
    assign dma_ready=active&&owner==3&&mem_ready;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin active<=0;owner<=0;mem_we<=0;mem_addr<=0;mem_wdata<=0;end
        else if(active) begin if(mem_ready) active<=0;end
        else if(dma_lease) begin
            if(dma_req) begin
                active<=1;owner<=3;mem_we<=1;mem_addr<=dma_addr;mem_wdata<=dma_wdata;
            end
        end else if(d_req) begin
            active<=1;owner<=2;mem_we<=d_we;mem_addr<=d_addr;mem_wdata<={d_wdata[255:66],d_wdata65_holdbuf,d_wdata[64:0]};
        end else if(i_req) begin
            active<=1;owner<=1;mem_we<=0;mem_addr<=i_addr;mem_wdata<=0;
        end
    end
endmodule
