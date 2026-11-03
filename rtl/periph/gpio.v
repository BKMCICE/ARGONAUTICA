// gpio.v - LED output / KEY input with edge-triggered interrupt.
//   0x00 OUT    : R/W output register (LEDs)
//   0x04 IN     : R   synchronized inputs (KEYs, active-low on board)
//   0x08 IRQ_EN : R/W per-input falling-edge interrupt enable
//   0x0C IRQ_ST : R   pending flags ; W1C
module gpio #(
    parameter N_OUT = 8,
    parameter N_IN  = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready,
    output wire        irq,
    output reg  [N_OUT-1:0] gpio_out,
    input  wire [N_IN-1:0]  gpio_in
);
    assign ready = 1'b1;

    reg [N_IN-1:0] in_s0, in_s1, in_s2;
    always @(posedge clk) begin
        in_s0 <= gpio_in; in_s1 <= in_s0; in_s2 <= in_s1;
    end
    wire [N_IN-1:0] fall = in_s2 & ~in_s1;

    reg [N_IN-1:0] irq_en, irq_st;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_out <= 0; irq_en <= 0; irq_st <= 0;
        end else begin
            irq_st <= (irq_st | (fall & irq_en));
            if (req && we) begin
                case (addr[3:2])
                    2'd0: gpio_out <= wdata[N_OUT-1:0];
                    2'd2: irq_en   <= wdata[N_IN-1:0];
                    2'd3: irq_st   <= (irq_st | (fall & irq_en)) & ~wdata[N_IN-1:0];
                    default: ;
                endcase
            end
        end
    end
    always @(*) begin
        case (addr[3:2])
            2'd0: rdata = {{(32-N_OUT){1'b0}}, gpio_out};
            2'd1: rdata = {{(32-N_IN){1'b0}}, in_s1};
            2'd2: rdata = {{(32-N_IN){1'b0}}, irq_en};
            default: rdata = {{(32-N_IN){1'b0}}, irq_st};
        endcase
    end
    assign irq = |irq_st;
endmodule
