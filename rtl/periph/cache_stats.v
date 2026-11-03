// Per-cache hit/miss counts for measuring the live DDR memory system.
// 0x00 CTRL: bit0 enable, bit1 clear all counters
// 0x04 I hits; 0x08 I misses; 0x0c D hits; 0x10 D misses
// Accepted events reach the counters one clock later. A clear discards
// queued events as well as the counts; enable is sampled with each event.
module cache_stats #(
    // Physical experiment only. Keep the original counter implementation
    // unless explicitly selected; MMIO/event timing is identical.
    parameter SPLIT_COUNTERS = 0
)(
    input wire clk,
    input wire rst_n,
    input wire req,
    input wire we,
    input wire [3:0] be,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    output wire ready,
    input wire i_hit,
    input wire i_miss,
    input wire d_hit,
    input wire d_miss
);
    assign ready = 1'b1;
    reg enable;
    reg [3:0] pending_events;
    reg [31:0] ihits, imisses, dhits, dmisses;
    wire clear = req && we && addr[4:2] == 0 && wdata[1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable <= 1'b1;
            pending_events <= 0;
        end else begin
            // Cut the cache tag-comparison -> wide counter-enable path.
            // Qualify here so disabling cannot lose an already accepted
            // event, and enabling cannot count an event sampled disabled.
            pending_events <= {i_hit, i_miss, d_hit, d_miss} & {4{enable && !clear}};
            if (req && we && addr[4:2] == 0) enable <= wdata[0];
        end
    end
    generate if (SPLIT_COUNTERS == 0) begin : original_counters
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                ihits <= 0; imisses <= 0; dhits <= 0; dmisses <= 0;
            end else if (clear) begin
                ihits <= 0; imisses <= 0; dhits <= 0; dmisses <= 0;
            end else begin
                if (pending_events[3]) ihits <= ihits + 1'b1;
                if (pending_events[2]) imisses <= imisses + 1'b1;
                if (pending_events[1]) dhits <= dhits + 1'b1;
                if (pending_events[0]) dmisses <= dmisses + 1'b1;
            end
        end
    end else begin : split_counters
        // Independent byte carry predicates keep clear out of a full-width
        // counter-enable cascade. All predicates use the same pre-edge count,
        // so updates, modulo-2^32 wrap and clear priority remain cycle-exact.
        genvar byte_index;
        for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin : bytes
            wire [3:0] increment;
            if (byte_index == 0) begin : low_byte
                assign increment = pending_events;
            end else begin : upper_byte
                assign increment = pending_events & {
                    (&ihits[byte_index*8-1:0]),
                    (&imisses[byte_index*8-1:0]),
                    (&dhits[byte_index*8-1:0]),
                    (&dmisses[byte_index*8-1:0])};
            end
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    ihits[byte_index*8 +: 8] <= 0;
                    imisses[byte_index*8 +: 8] <= 0;
                    dhits[byte_index*8 +: 8] <= 0;
                    dmisses[byte_index*8 +: 8] <= 0;
                end else if (clear) begin
                    ihits[byte_index*8 +: 8] <= 0;
                    imisses[byte_index*8 +: 8] <= 0;
                    dhits[byte_index*8 +: 8] <= 0;
                    dmisses[byte_index*8 +: 8] <= 0;
                end else begin
                    if (increment[3]) ihits[byte_index*8 +: 8] <= ihits[byte_index*8 +: 8] + 1'b1;
                    if (increment[2]) imisses[byte_index*8 +: 8] <= imisses[byte_index*8 +: 8] + 1'b1;
                    if (increment[1]) dhits[byte_index*8 +: 8] <= dhits[byte_index*8 +: 8] + 1'b1;
                    if (increment[0]) dmisses[byte_index*8 +: 8] <= dmisses[byte_index*8 +: 8] + 1'b1;
                end
            end
        end
    end endgenerate
    always @(*) begin
        case (addr[4:2])
            0: rdata = {31'b0, enable};
            1: rdata = ihits;
            2: rdata = imisses;
            3: rdata = dhits;
            4: rdata = dmisses;
            default: rdata = 0;
        endcase
    end
endmodule
