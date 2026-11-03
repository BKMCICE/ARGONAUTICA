// soc_bus.v - simple single-master bus: address decode + slave mux.
// The core's data port is presented to one of N slaves selected by the
// upper address bits. Each slave uses the same req/we/be/addr/wdata/rdata/ready
// interface as rv_core. Slaves must hold rdata stable through the cycle
// in which they assert ready.
module soc_bus #(
    parameter N_SLAVES = 6,
    // Enable only when the address decoder guarantees at most one select.
    parameter ONE_HOT_SELECT = 0
)(
    // master (rv_core data port)
    input  wire        m_req,
    input  wire        m_we,
    input  wire [3:0]  m_be,
    input  wire [31:0] m_addr,
    input  wire [31:0] m_wdata,
    output reg  [31:0] m_rdata,
    output reg         m_ready,
    output wire        m_fault,

    // slave select: which slave the address maps to (0 = none)
    input  wire [N_SLAVES-1:0] sel,

    // slaves (flattened)
    output wire [N_SLAVES-1:0]    s_req,
    output wire                   s_we,
    output wire [3:0]             s_be,
    output wire [31:0]            s_addr,
    output wire [31:0]            s_wdata,
    input  wire [N_SLAVES*32-1:0] s_rdata,
    input  wire [N_SLAVES-1:0]    s_ready
);
    assign s_req   = sel & {N_SLAVES{m_req}};
    // Address validity is independent of m_req, allowing MEM to decide the
    // trap before issuing a request without a combinational feedback loop.
    assign m_fault = ~(|sel);
    assign s_we    = m_we;
    assign s_be    = m_be;
    assign s_addr  = m_addr;
    assign s_wdata = m_wdata;

    generate if (ONE_HOT_SELECT) begin : g_one_hot
        integer i;
        always @(*) begin
            m_rdata = 0;
            m_ready = |(sel & s_ready);
            for (i = 0; i < N_SLAVES; i = i + 1)
                m_rdata = m_rdata | (s_rdata[i*32 +: 32] & {32{sel[i]}});
            if (!(|sel)) begin
                m_rdata = 32'hDEAD_BEEF;
                m_ready = 1'b1;
            end
        end
    end else begin : g_priority
        integer i;
        always @(*) begin
        m_rdata = 32'hDEAD_BEEF;
        m_ready = 1'b1;        // unmapped access completes immediately
        for (i = 0; i < N_SLAVES; i = i + 1) begin
            if (sel[i]) begin
                m_rdata = s_rdata[i*32 +: 32];
                m_ready = s_ready[i];
            end
        end
        end
    end endgenerate
endmodule
