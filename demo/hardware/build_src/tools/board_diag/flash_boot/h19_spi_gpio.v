// H19 private runtime configuration-Flash IO, software bit-banged mode0.
// Accepted stores come only from GPIO+0x10; the original GPIO stays unchanged.
// Not an SPI command engine: readonly boot/probe firmware restricts opcodes9F/03.
module h19_spi_gpio(
    input wire clk,rst_n,request,we,
    input wire [3:0] be,input wire [31:0] wdata,
    input wire flash_miso,
    output wire [31:0] rdata,
    output wire flash_cs_n,flash_sck,flash_mosi,flash_wp_n,flash_hold_n
);
    reg [2:0] control=3'b100;
    (* async_reg="true" *) reg [1:0] miso_sync=0;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin control<=3'b100;miso_sync<=0;end
        else begin
            miso_sync<={miso_sync[0],flash_miso};
            if(request&&we&&(&be))control<=wdata[2:0];
        end
    assign flash_sck=control[0];
    assign flash_mosi=control[1];
    assign flash_cs_n=control[2];
    assign flash_wp_n=1'b1;
    assign flash_hold_n=1'b1;
    assign rdata={16'h4832,12'd0,miso_sync[1],control};
endmodule
