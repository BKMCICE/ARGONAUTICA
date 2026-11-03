// uart.v - memory-mapped UART (8N1) with 16-byte TX/RX FIFOs.
// Register map (word offsets from base):
//   0x00 DATA   : W = push TX byte ; R = pop RX byte (bit 8 = rx valid)
//   0x04 STATUS : [0] tx_full [1] tx_empty [2] rx_valid [3] rx_overrun
//   0x08 DIV    : R/W clock divisor = CLK_HZ / BAUD (16-bit)
//   0x0C IRQ_EN : [0] rx_irq_en ; irq asserted when rx fifo non-empty
module uart #(
    parameter CLK_HZ   = 100_000_000,
    parameter BAUD     = 115200
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
    input  wire        rxd,
    output reg         txd
);
    assign ready = 1'b1;

    reg [15:0] div;
    reg        rx_irq_en;
    reg        rx_overrun;

    // ---------------- TX FIFO + shifter ----------------
    reg [7:0] tx_fifo [0:15];
    reg [4:0] tx_wp, tx_rp;
    wire tx_empty = (tx_wp == tx_rp);
    wire tx_full  = (tx_wp[3:0] == tx_rp[3:0]) && (tx_wp[4] != tx_rp[4]);

    reg [15:0] tx_cnt;
    reg [3:0]  tx_bit;      // 0 idle, 1 start, 2..9 data, 10 stop
    reg [7:0]  tx_sh;

    wire wr_data = req & we & (addr[3:2] == 2'd0) & be[0];
    wire rd_data = req & ~we & (addr[3:2] == 2'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_wp <= 0; tx_rp <= 0; tx_cnt <= 0; tx_bit <= 0; tx_sh <= 0; txd <= 1'b1;
        end else begin
            if (wr_data && !tx_full) begin
                tx_fifo[tx_wp[3:0]] <= wdata[7:0];
                tx_wp <= tx_wp + 5'd1;
            end
            if (tx_bit == 4'd0) begin
                txd <= 1'b1;
                if (!tx_empty) begin
                    tx_sh  <= tx_fifo[tx_rp[3:0]];
                    tx_rp  <= tx_rp + 5'd1;
                    tx_bit <= 4'd1;
                    tx_cnt <= div - 16'd1;
                    txd    <= 1'b0;   // start bit
                end
            end else if (tx_cnt != 0) begin
                tx_cnt <= tx_cnt - 16'd1;
            end else begin
                tx_cnt <= div - 16'd1;
                if (tx_bit == 4'd10) begin
                    tx_bit <= 4'd0;
                end else begin
                    tx_bit <= tx_bit + 4'd1;
                    if (tx_bit == 4'd9) txd <= 1'b1;         // stop bit
                    else begin txd <= tx_sh[0]; tx_sh <= {1'b0, tx_sh[7:1]}; end
                end
            end
        end
    end

    // ---------------- RX sampler + FIFO ----------------
    reg [2:0] rx_sync;
    always @(posedge clk) rx_sync <= {rx_sync[1:0], rxd};
    wire rx_in = rx_sync[2];

    reg [7:0] rx_fifo [0:15];
    reg [4:0] rx_wp, rx_rp;
    wire rx_empty = (rx_wp == rx_rp);
    wire rx_full  = (rx_wp[3:0] == rx_rp[3:0]) && (rx_wp[4] != rx_rp[4]);

    reg [15:0] rx_cnt;
    reg [3:0]  rx_bit;      // 0 idle, 1 start(half), 2..9 data, 10 stop
    reg [7:0]  rx_sh;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_wp <= 0; rx_rp <= 0; rx_cnt <= 0; rx_bit <= 0; rx_sh <= 0; rx_overrun <= 0;
        end else begin
            if (rd_data && !rx_empty) rx_rp <= rx_rp + 5'd1;
            if (rx_bit == 4'd0) begin
                if (!rx_in) begin            // start edge
                    rx_bit <= 4'd1;
                    rx_cnt <= {1'b0, div[15:1]} - 16'd1;   // half bit
                end
            end else if (rx_cnt != 0) begin
                rx_cnt <= rx_cnt - 16'd1;
            end else begin
                rx_cnt <= div - 16'd1;
                if (rx_bit == 4'd1) begin
                    if (rx_in) rx_bit <= 4'd0;   // false start
                    else       rx_bit <= 4'd2;
                end else if (rx_bit == 4'd10) begin
                    rx_bit <= 4'd0;
                    if (rx_in) begin             // valid stop
                        if (!rx_full) begin
                            rx_fifo[rx_wp[3:0]] <= rx_sh;
                            rx_wp <= rx_wp + 5'd1;
                        end else rx_overrun <= 1'b1;
                    end
                end else begin
                    rx_sh  <= {rx_in, rx_sh[7:1]};
                    rx_bit <= rx_bit + 4'd1;
                end
            end
            if (req && we && addr[3:2] == 2'd1) rx_overrun <= 1'b0;  // W1C via STATUS write
        end
    end

    // ---------------- registers ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div       <= CLK_HZ / BAUD;
            rx_irq_en <= 1'b0;
        end else if (req && we) begin
            case (addr[3:2])
                2'd2: div       <= wdata[15:0];
                2'd3: rx_irq_en <= wdata[0];
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (addr[3:2])
            2'd0: rdata = {23'b0, ~rx_empty, rx_empty ? 8'h00 : rx_fifo[rx_rp[3:0]]};
            2'd1: rdata = {28'b0, rx_overrun, ~rx_empty, tx_empty, tx_full};
            2'd2: rdata = {16'b0, div};
            default: rdata = {31'b0, rx_irq_en};
        endcase
    end

    assign irq = rx_irq_en & ~rx_empty;
endmodule
