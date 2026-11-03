// soc_top.v - RV32 SoC: core + unified TCM + UART + GPIO + CLINT + perf counters.
// Memory map (see docs/pipeline_spec.md / PLAN.md section 2.2):
//   0x0000_0000 - 0x0000_FFFF  RAM (64 KB, instruction + data, DRM)
//   0x4000_0000  UART      0x4000_1000  GPIO
//   0x4000_2000  CLINT     0x4000_3000  PERF
// A board-level wrapper (rtl/top/pangu50k_top.v) supplies clock/reset and pins.
module soc_top #(
    parameter CLK_HZ        = 100_000_000,
    parameter BAUD          = 115200,
    parameter RAM_ADDR_W    = 14,            // words (64 KB)
    parameter RAM_INIT_FILE = "",
    parameter ENABLE_M      = 1,
    parameter ENABLE_BTB    = 0,
    parameter BTB_ENTRIES   = 32
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rxd,
    output wire       uart_txd,
    output wire [7:0] gpio_out,
    input  wire [7:0] gpio_in
);
    // ---------------- core ----------------
    wire        imem_req, imem_ready, imem_fault, dmem_req, dmem_we, dmem_ready, dmem_fault;
    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_be;
    wire        irq_sw, irq_tim, irq_ext;
    wire        ev_ret, ev_br, ev_mp, ev_lu, ev_is, ev_ds, ev_tr;

    rv_core #(
        .RESET_PC(32'h0000_0000), .ENABLE_M(ENABLE_M),
        .ENABLE_BTB(ENABLE_BTB), .BTB_ENTRIES(BTB_ENTRIES)
    ) u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_req(imem_req), .imem_addr(imem_addr), .imem_rdata(imem_rdata), .imem_ready(imem_ready), .imem_fault(imem_fault),
        .dmem_req(dmem_req), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready), .dmem_fault(dmem_fault),
        .irq_software(irq_sw), .irq_timer(irq_tim), .irq_external(irq_ext),
        .ev_instr_retired(ev_ret), .ev_branch(ev_br), .ev_branch_mispred(ev_mp),
        .ev_load_use_stall(ev_lu), .ev_imem_stall(ev_is), .ev_dmem_stall(ev_ds), .ev_trap(ev_tr)
    );

    // ---------------- address decode ----------------
    localparam S_RAM = 0, S_UART = 1, S_GPIO = 2, S_CLINT = 3, S_PERF = 4;
    localparam NS = 5;
    wire [NS-1:0] sel;
    assign sel[S_RAM]   = (dmem_addr[31:RAM_ADDR_W+2] == 0);
    assign sel[S_UART]  = (dmem_addr[31:12] == 20'h40000);
    assign sel[S_GPIO]  = (dmem_addr[31:12] == 20'h40001);
    assign sel[S_CLINT] = (dmem_addr[31:12] == 20'h40002);
    assign sel[S_PERF]  = (dmem_addr[31:12] == 20'h40003);

    wire [NS-1:0]    s_req, s_ready;
    wire             s_we;
    wire [3:0]       s_be;
    wire [31:0]      s_addr, s_wdata;
    wire [NS*32-1:0] s_rdata;

    soc_bus #(.N_SLAVES(NS)) u_bus (
        .m_req(dmem_req), .m_we(dmem_we), .m_be(dmem_be), .m_addr(dmem_addr), .m_wdata(dmem_wdata),
        .m_rdata(dmem_rdata), .m_ready(dmem_ready), .m_fault(dmem_fault), .sel(sel),
        .s_req(s_req), .s_we(s_we), .s_be(s_be), .s_addr(s_addr), .s_wdata(s_wdata),
        .s_rdata(s_rdata), .s_ready(s_ready)
    );

    // ---------------- RAM ----------------
    soc_ram #(.ADDR_WIDTH(RAM_ADDR_W), .INIT_FILE(RAM_INIT_FILE)) u_ram (
        .clk(clk), .rst_n(rst_n),
        .i_req(imem_req), .i_addr(imem_addr), .i_rdata(imem_rdata), .i_ready(imem_ready), .i_fault(imem_fault),
        .d_req(s_req[S_RAM]), .d_we(s_we), .d_be(s_be), .d_addr(s_addr), .d_wdata(s_wdata),
        .d_rdata(s_rdata[S_RAM*32 +: 32]), .d_ready(s_ready[S_RAM])
    );

    // ---------------- peripherals ----------------
    wire uart_irq, gpio_irq;
    uart #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_UART]), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(s_rdata[S_UART*32 +: 32]), .ready(s_ready[S_UART]),
        .irq(uart_irq), .rxd(uart_rxd), .txd(uart_txd)
    );
    gpio #(.N_OUT(8), .N_IN(8)) u_gpio (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_GPIO]), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(s_rdata[S_GPIO*32 +: 32]), .ready(s_ready[S_GPIO]),
        .irq(gpio_irq), .gpio_out(gpio_out), .gpio_in(gpio_in)
    );
    clint u_clint (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_CLINT]), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(s_rdata[S_CLINT*32 +: 32]), .ready(s_ready[S_CLINT]),
        .msip(irq_sw), .mtip(irq_tim)
    );
    perf_counter u_perf (
        .clk(clk), .rst_n(rst_n), .req(s_req[S_PERF]), .we(s_we), .be(s_be), .addr(s_addr),
        .wdata(s_wdata), .rdata(s_rdata[S_PERF*32 +: 32]), .ready(s_ready[S_PERF]),
        .events({ev_tr, ev_ds, ev_is, ev_lu, ev_mp, ev_br, ev_ret, 1'b1})
    );

    assign irq_ext = uart_irq | gpio_irq;
endmodule
