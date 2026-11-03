// Two-way write-back cache, 32-byte lines, 64 sets (4 KiB total).
// One CPU request is accepted at a time. The backing interface transfers a
// whole line; a DDR adapter can map one line to a native 256-bit burst beat.
// Instruction caches tie cpu_we low. invalidate clears tags (e.g. FENCE.I).
module rv_cache_2way #(
    parameter SET_BITS = 6,
    // Default preserves the original asynchronous tag arrays. Optional tags
    // are read in the preceding IDLE/flush-advance cycle, without new states.
    parameter TAG_STORAGE = 0
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         invalidate,
    input  wire         flush_req,
    output wire         flush_done,
    input  wire         cpu_req,
    input  wire         cpu_we,
    input  wire [3:0]   cpu_be,
    input  wire [31:0]  cpu_addr,
    input  wire [31:0]  cpu_wdata,
    output wire [31:0]  cpu_rdata,
    output wire         cpu_ready,
    output wire         hit_event,
    output wire         miss_event,
    output wire         line_req,
    output wire         line_we,
    output wire [31:0]  line_addr,
    output wire [255:0] line_wdata,
    input  wire [255:0] line_rdata,
    input  wire         line_ready
);
    localparam SETS = 1 << SET_BITS;
    localparam TAG_BITS = 27 - SET_BITS;
    localparam S_IDLE = 4'd0, S_WB = 4'd1, S_FILL = 4'd2, S_RESP = 4'd3;
    localparam S_FCHECK = 4'd4, S_FWB = 4'd5, S_FDONE = 4'd6, S_LOOKUP = 4'd7;
    localparam S_HIT = 4'd8;
    reg [3:0] state;

    reg [255:0] data0 [0:SETS-1];
    reg [255:0] data1 [0:SETS-1];
    reg [TAG_BITS-1:0] tag0 [0:SETS-1];
    reg [TAG_BITS-1:0] tag1 [0:SETS-1];
    reg [SETS-1:0] valid0, valid1, dirty0, dirty1, lru;

    reg [31:0] pending_addr, pending_wdata;
    reg [3:0] pending_be;
    reg pending_we, pending_victim;
    reg pending_hit0;
    reg [SET_BITS-1:0] pending_set;
    reg [TAG_BITS-1:0] pending_tag, evicted_tag;
    reg [255:0] evicted_data;
    reg [31:0] response_data;
    reg [SET_BITS-1:0] flush_set;
    reg flush_way;

    // The request register separates the CPU/SoC address path from tag
    // comparison and wide data-RAM write enables.
    wire [SET_BITS-1:0] set_idx = pending_addr[SET_BITS+4:5];
    wire [TAG_BITS-1:0] tag = pending_addr[31:SET_BITS+5];
    wire [TAG_BITS-1:0] stored_tag0, stored_tag1;
    wire [TAG_BITS-1:0] lookup_tag0 = TAG_STORAGE == 0 ? tag0[set_idx] : stored_tag0;
    wire [TAG_BITS-1:0] lookup_tag1 = TAG_STORAGE == 0 ? tag1[set_idx] : stored_tag1;
    wire [TAG_BITS-1:0] flush_tag0 = TAG_STORAGE == 0 ? tag0[flush_set] : stored_tag0;
    wire [TAG_BITS-1:0] flush_tag1 = TAG_STORAGE == 0 ? tag1[flush_set] : stored_tag1;
    wire hit0 = valid0[set_idx] && lookup_tag0 == tag;
    wire hit1 = valid1[set_idx] && lookup_tag1 == tag;
    wire victim = !valid0[set_idx] ? 1'b0 : !valid1[set_idx] ? 1'b1 : lru[set_idx];
    wire victim_dirty = victim ? (valid1[set_idx] && dirty1[set_idx]) :
                                  (valid0[set_idx] && dirty0[set_idx]);

    // CPU tag read: consume cpu_addr on the edge that accepts the request,
    // so the sampled tags already match pending_addr during S_LOOKUP.
    // Flush reads both ways at set zero on entry, and prefetches the next
    // set only when advancing past way1. S_FWB retains that set under stalls.
    wire flush_current_dirty = flush_way ? (valid1[flush_set] && dirty1[flush_set]) :
                                           (valid0[flush_set] && dirty0[flush_set]);
    wire tag_read_cpu = state == S_IDLE && !flush_req && cpu_req && !invalidate;
    wire tag_read_flush_start = state == S_IDLE && flush_req;
    wire tag_read_flush_next = flush_way && flush_set != SETS-1 &&
        ((state == S_FCHECK && !flush_current_dirty) ||
         (state == S_FWB && line_ready));
    wire tag_read_enable = rst_n && (tag_read_cpu || tag_read_flush_start || tag_read_flush_next);
    wire [SET_BITS-1:0] tag_read_set = tag_read_flush_start ? {SET_BITS{1'b0}} :
        tag_read_flush_next ? flush_set + 1'b1 : cpu_addr[SET_BITS+4:5];
    wire tag_write_enable = rst_n && state == S_FILL && line_ready;
    generate if (TAG_STORAGE != 0) begin : optional_tags
        rv_cache_tag_store #(.SET_BITS(SET_BITS),.TAG_BITS(TAG_BITS),.STORAGE(TAG_STORAGE)) way0 (
            .clk(clk),.write_enable(tag_write_enable && !pending_victim),
            .write_set(pending_set),.write_tag(pending_tag),
            .read_enable(tag_read_enable),.read_set(tag_read_set),.read_tag(stored_tag0));
        rv_cache_tag_store #(.SET_BITS(SET_BITS),.TAG_BITS(TAG_BITS),.STORAGE(TAG_STORAGE)) way1 (
            .clk(clk),.write_enable(tag_write_enable && pending_victim),
            .write_set(pending_set),.write_tag(pending_tag),
            .read_enable(tag_read_enable),.read_set(tag_read_set),.read_tag(stored_tag1));
    end else begin : original_tags
        assign stored_tag0 = {TAG_BITS{1'b0}};
        assign stored_tag1 = {TAG_BITS{1'b0}};
    end endgenerate

    function [255:0] store_bytes;
        input [255:0] old_line;
        input [2:0] word_index;
        input [31:0] value;
        input [3:0] byte_enable;
        reg [255:0] new_line;
        integer lane;
        begin
            new_line = old_line;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (byte_enable[lane])
                    new_line[word_index*32 + lane*8 +: 8] = value[lane*8 +: 8];
            store_bytes = new_line;
        end
    endfunction

    assign cpu_ready = state == S_RESP;
    assign cpu_rdata = response_data;
    assign flush_done = state == S_FDONE;
    assign hit_event = state == S_LOOKUP && !invalidate && (hit0 || hit1);
    assign miss_event = state == S_LOOKUP && !invalidate && !(hit0 || hit1);
    assign line_req = state == S_WB || state == S_FILL || state == S_FWB;
    assign line_we = state == S_WB || state == S_FWB;
    assign line_addr = state == S_FWB ?
                       {flush_way ? flush_tag1 : flush_tag0, flush_set, 5'b0} :
                       state == S_WB ? {evicted_tag, pending_set, 5'b0} :
                                       {pending_addr[31:5], 5'b0};
    assign line_wdata = state == S_FWB ?
                        (flush_way ? data1[flush_set] : data0[flush_set]) : evicted_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            valid0 <= {SETS{1'b0}};
            valid1 <= {SETS{1'b0}};
            dirty0 <= {SETS{1'b0}};
            dirty1 <= {SETS{1'b0}};
            lru <= {SETS{1'b0}};
            pending_addr <= 0;
            pending_wdata <= 0;
            pending_be <= 0;
            pending_we <= 0;
            pending_victim <= 0;
            pending_hit0 <= 0;
            pending_set <= 0;
            pending_tag <= 0;
            evicted_tag <= 0;
            evicted_data <= 0;
            response_data <= 0;
            flush_set <= 0;
            flush_way <= 0;
        end else begin
            case (state)
                S_IDLE: if (flush_req) begin
                    flush_set <= 0;
                    flush_way <= 0;
                    state <= S_FCHECK;
                end else if (cpu_req && !invalidate) begin
                    pending_addr <= cpu_addr;
                    pending_wdata <= cpu_wdata;
                    pending_be <= cpu_be;
                    pending_we <= cpu_we;
                    state <= S_LOOKUP;
                end
                S_LOOKUP: if (invalidate) state <= S_IDLE;
                else begin
                    if (hit0 || hit1) begin
                        pending_hit0 <= hit0;
                        state <= S_HIT;
                    end else begin
                        pending_victim <= victim;
                        pending_set <= set_idx;
                        pending_tag <= tag;
                        evicted_tag <= victim ? lookup_tag1 : lookup_tag0;
                        evicted_data <= victim ? data1[set_idx] : data0[set_idx];
                        state <= victim_dirty ? S_WB : S_FILL;
                    end
                end
                // Register the tag result before it controls the wide data
                // RAM write path. A hit takes one extra cycle, but the tag
                // lookup and data-array update no longer share a timing path.
                S_HIT: if (invalidate) state <= S_IDLE;
                else begin
                    response_data <= pending_hit0 ? data0[set_idx][pending_addr[4:2]*32 +: 32] :
                                                    data1[set_idx][pending_addr[4:2]*32 +: 32];
                    lru[set_idx] <= pending_hit0;
                    if (pending_we) begin
                        if (pending_hit0) begin
                            data0[set_idx] <= store_bytes(data0[set_idx], pending_addr[4:2], pending_wdata, pending_be);
                            dirty0[set_idx] <= 1'b1;
                        end else begin
                            data1[set_idx] <= store_bytes(data1[set_idx], pending_addr[4:2], pending_wdata, pending_be);
                            dirty1[set_idx] <= 1'b1;
                        end
                    end
                    state <= S_RESP;
                end
                S_WB: if (line_ready) state <= S_FILL;
                S_FILL: if (line_ready) begin
                    if (pending_victim) begin
                        data1[pending_set] <= pending_we ?
                            store_bytes(line_rdata, pending_addr[4:2], pending_wdata, pending_be) : line_rdata;
                        if (TAG_STORAGE == 0) tag1[pending_set] <= pending_tag;
                        valid1[pending_set] <= 1'b1;
                        dirty1[pending_set] <= pending_we;
                    end else begin
                        data0[pending_set] <= pending_we ?
                            store_bytes(line_rdata, pending_addr[4:2], pending_wdata, pending_be) : line_rdata;
                        if (TAG_STORAGE == 0) tag0[pending_set] <= pending_tag;
                        valid0[pending_set] <= 1'b1;
                        dirty0[pending_set] <= pending_we;
                    end
                    response_data <= line_rdata[pending_addr[4:2]*32 +: 32];
                    lru[pending_set] <= ~pending_victim;
                    state <= S_RESP;
                end
                S_RESP: state <= S_IDLE;
                S_FCHECK: begin
                    if (flush_way ? (valid1[flush_set] && dirty1[flush_set]) :
                                    (valid0[flush_set] && dirty0[flush_set]))
                        state <= S_FWB;
                    else if (!flush_way) flush_way <= 1'b1;
                    else if (flush_set == SETS-1) state <= S_FDONE;
                    else begin
                        flush_way <= 1'b0;
                        flush_set <= flush_set + 1'b1;
                    end
                end
                S_FWB: if (line_ready) begin
                    if (flush_way) dirty1[flush_set] <= 1'b0;
                    else           dirty0[flush_set] <= 1'b0;
                    if (!flush_way) begin
                        flush_way <= 1'b1;
                        state <= S_FCHECK;
                    end else if (flush_set == SETS-1) state <= S_FDONE;
                    else begin
                        flush_way <= 1'b0;
                        flush_set <= flush_set + 1'b1;
                        state <= S_FCHECK;
                    end
                end
                S_FDONE: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
            // Invalidate only after dirty data has been flushed. This has
            // priority over a simultaneous line fill into the I-cache.
            if (invalidate) begin
                valid0 <= {SETS{1'b0}};
                valid1 <= {SETS{1'b0}};
            end
        end
    end
endmodule
