// Read-only equivalent of rv_cache_2way for the instruction port only.
// LOOKUP samples both synchronous data ways; HIT consumes that sample on
// the next edge. Refills bypass RAM to the response, matching the old timing.
module rv_icache_drm #(
    parameter EARLY_READ = 0,
    parameter SET_BITS = 6
)(
    input wire clk, rst_n,
    input wire invalidate, flush_req,
    output wire flush_done,
    input wire cpu_req,
    input wire [31:0] cpu_addr,
    output wire [31:0] cpu_rdata,
    output wire cpu_ready, hit_event, miss_event,
    output wire line_req, line_we,
    output wire [31:0] line_addr,
    output wire [255:0] line_wdata,
    input wire [255:0] line_rdata,
    input wire line_ready
);
    localparam SETS = 1 << SET_BITS;
    localparam TAG_BITS = 27 - SET_BITS;
    localparam S_IDLE=4'd0, S_FILL=4'd2, S_RESP=4'd3;
    localparam S_FCHECK=4'd4, S_FDONE=4'd6, S_LOOKUP=4'd7, S_HIT=4'd8;
    reg [3:0] state;
    reg [TAG_BITS-1:0] tag0 [0:SETS-1], tag1 [0:SETS-1];
    reg [SETS-1:0] valid0, valid1, lru;
    reg [31:0] pending_addr, response_data;
    reg [SET_BITS-1:0] pending_set, flush_set;
    reg [TAG_BITS-1:0] pending_tag;
    reg pending_victim, pending_hit0, flush_way;
    wire [SET_BITS-1:0] set_idx = pending_addr[SET_BITS+4:5];
    wire [TAG_BITS-1:0] tag = pending_addr[31:SET_BITS+5];
    wire hit0 = valid0[set_idx] && tag0[set_idx] == tag;
    wire hit1 = valid1[set_idx] && tag1[set_idx] == tag;
    wire victim = !valid0[set_idx] ? 1'b0 : !valid1[set_idx] ? 1'b1 : lru[set_idx];
    wire [255:0] read_line0, read_line1;
    wire refill = rst_n && state == S_FILL && line_ready;
    wire lookup = rst_n && state == S_LOOKUP;
    // Optional early synchronous read: address is accepted on this same edge.
    wire accept_read = rst_n && state == S_IDLE && cpu_req && !invalidate && !flush_req;
    wire ram_read = EARLY_READ ? accept_read : lookup;
    wire [SET_BITS-1:0] ram_set = EARLY_READ ? cpu_addr[SET_BITS+4:5] : set_idx;
    rv_icache_line_ram #(.SET_BITS(SET_BITS)) way0 (
        .clk(clk),.write_enable(refill && !pending_victim),
        .write_set(pending_set),.write_line(line_rdata),
        .read_enable(ram_read),.read_set(ram_set),.read_line(read_line0));
    rv_icache_line_ram #(.SET_BITS(SET_BITS)) way1 (
        .clk(clk),.write_enable(refill && pending_victim),
        .write_set(pending_set),.write_line(line_rdata),
        .read_enable(ram_read),.read_set(ram_set),.read_line(read_line1));
    assign cpu_ready = state == S_RESP;
    assign cpu_rdata = response_data;
    assign flush_done = state == S_FDONE;
    assign hit_event = state == S_LOOKUP && !invalidate && (hit0 || hit1);
    assign miss_event = state == S_LOOKUP && !invalidate && !(hit0 || hit1);
    assign line_req = state == S_FILL;
    assign line_we = 1'b0;
    assign line_addr = {pending_addr[31:5],5'b0};
    assign line_wdata = 256'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            valid0 <= 0; valid1 <= 0; lru <= 0;
            pending_addr <= 0; pending_set <= 0; pending_tag <= 0;
            pending_victim <= 0; pending_hit0 <= 0;
            response_data <= 0; flush_set <= 0; flush_way <= 0;
        end else begin
            case (state)
                S_IDLE: if (flush_req) begin
                    flush_set <= 0; flush_way <= 0; state <= S_FCHECK;
                end else if (cpu_req && !invalidate) begin
                    pending_addr <= cpu_addr; state <= S_LOOKUP;
                end
                S_LOOKUP: if (invalidate) state <= S_IDLE;
                else if (hit0 || hit1) begin
                    if (EARLY_READ) begin
                        response_data <= hit0 ? read_line0[pending_addr[4:2]*32 +: 32] :
                                                read_line1[pending_addr[4:2]*32 +: 32];
                        lru[set_idx] <= hit0;
                        state <= S_RESP;
                    end else begin pending_hit0 <= hit0; state <= S_HIT; end
                end else begin
                    pending_victim <= victim; pending_set <= set_idx;
                    pending_tag <= tag; state <= S_FILL;
                end
                S_HIT: if (invalidate) state <= S_IDLE;
                else begin
                    response_data <= pending_hit0 ? read_line0[pending_addr[4:2]*32 +: 32] :
                                                    read_line1[pending_addr[4:2]*32 +: 32];
                    lru[set_idx] <= pending_hit0;
                    state <= S_RESP;
                end
                S_FILL: if (line_ready) begin
                    if (pending_victim) begin
                        tag1[pending_set] <= pending_tag;
                        valid1[pending_set] <= 1'b1;
                    end else begin
                        tag0[pending_set] <= pending_tag;
                        valid0[pending_set] <= 1'b1;
                    end
                    response_data <= line_rdata[pending_addr[4:2]*32 +: 32];
                    lru[pending_set] <= ~pending_victim;
                    state <= S_RESP;
                end
                S_RESP: state <= S_IDLE;
                // Match the old read-only cache's no-dirty-line flush walk.
                S_FCHECK: if (!flush_way) flush_way <= 1'b1;
                else if (flush_set == SETS-1) state <= S_FDONE;
                else begin flush_way <= 1'b0; flush_set <= flush_set + 1'b1; end
                S_FDONE: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
            // Preserve the old priority, including invalidate on a fill edge.
            if (invalidate) begin valid0 <= 0; valid1 <= 0; end
        end
    end
endmodule
