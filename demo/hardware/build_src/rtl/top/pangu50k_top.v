// pangu50k_top.v - board top for MES50HP (PGL50H): clock, reset, pins.
// sys_clk 50 MHz (P20) -> PLL -> cpu_clk (CPU_MHZ). KEY1 (K18, active-low)
// is the CPU reset. LED1..8 = gpio_out. UART on CP2102 (R9 tx / R8 rx).
module pangu50k_top #(
    parameter CPU_MHZ       = 100,
    parameter RAM_INIT_FILE = "",
    parameter ENABLE_M      = 1,
    parameter ENABLE_BTB    = 0,
    parameter RAM_ADDR_W    = 14             // 64 KB on-chip RAM (words)
)(
    input  wire       sys_clk,
    input  wire [7:0] key,
    output wire [7:0] led,
    input  wire       uart_rx,
    output wire       uart_tx
);
    wire cpu_clk, pll_lock;
    pll_sys #(.RATIOI(1), .RATIOF(20), .RATIO0(1000 / CPU_MHZ)) u_pll (
        .clkin(sys_clk), .rst(1'b0), .clkout0(cpu_clk), .lock(pll_lock)
    );

    // reset: hold while PLL unlocked or key pressed, release synchronously
    wire key_rst_n = key[0];
    reg [3:0] rst_sync = 4'b0;
    always @(posedge cpu_clk or negedge key_rst_n) begin
        if (!key_rst_n) rst_sync <= 4'b0;
        else            rst_sync <= {rst_sync[2:0], pll_lock};
    end
    wire rst_n = rst_sync[3];

    soc_top #(
        .CLK_HZ(CPU_MHZ * 1_000_000), .BAUD(115200), .RAM_ADDR_W(RAM_ADDR_W),
        .RAM_INIT_FILE(RAM_INIT_FILE), .ENABLE_M(ENABLE_M), .ENABLE_BTB(ENABLE_BTB)
    ) u_soc (
        .clk(cpu_clk), .rst_n(rst_n),
        .uart_rxd(uart_rx), .uart_txd(uart_tx),
        .gpio_out(led), .gpio_in(key)
    );
endmodule
