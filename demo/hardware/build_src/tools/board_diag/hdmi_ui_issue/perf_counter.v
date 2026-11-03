// H04U private perf_counter: same-edge byte carry segmentation.
// ABI, address aliases, ignored byte enables, and old-enable semantics match
// rtl/periph/perf_counter.v. This is a timing candidate, not a timing result.
module perf_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready,
    input  wire [7:0]  events
);
    assign ready = 1'b1;
    reg en;
    reg [31:0] cnt [0:7];
    wire clr = req & we & (addr[5:2] == 4'd0) & wdata[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) en <= 1'b0;
        else if (req && we && addr[5:2] == 4'd0) en <= wdata[0];
    end

    // All carry predicates observe the PRE-edge count. There is no pending
    // event or clear register: each enabled event remains visible immediately
    // after the same edge, including modulo-2^32 wrap and enable transitions.
    genvar event_index, byte_index;
    generate
        for (event_index = 0; event_index < 8; event_index = event_index + 1) begin : counters
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin : bytes
                wire carry;
                if (byte_index == 0) begin : low_byte
                    assign carry = 1'b1;
                end else begin : high_byte
                    assign carry = &cnt[event_index][byte_index*8-1:0];
                end
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) cnt[event_index][byte_index*8 +: 8] <= 8'b0;
                    else if (clr) cnt[event_index][byte_index*8 +: 8] <= 8'b0;
                    else if (en && events[event_index]) begin
                        if (carry) cnt[event_index][byte_index*8 +: 8]
                            <= cnt[event_index][byte_index*8 +: 8] + 8'd1;
                    end
                end
            end
        end
    endgenerate

    always @(*) begin
        if (addr[5:2] == 4'd0) rdata = {31'b0, en};
        else if (addr[5:2] <= 4'd8) rdata = cnt[addr[5:2] - 4'd1];
        else rdata = 32'b0;
    end
endmodule
