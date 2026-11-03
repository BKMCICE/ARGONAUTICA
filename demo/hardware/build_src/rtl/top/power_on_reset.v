// A real startup reset keeps the DDR controller's FIFO reset logic in the
// synthesized design. Default hold: 65535 clocks, about 1.31 ms at 50 MHz.
module power_on_reset #(
    parameter COUNTER_BITS = 16
) (
    input wire clk,
    output wire rst_n
);
    reg [COUNTER_BITS-1:0] count = 0;
    assign rst_n = &count;
    always @(posedge clk) begin
        if (!rst_n) count <= count + 1'b1;
    end
endmodule
