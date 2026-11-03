// Adapts the core's one-cycle-ahead fetch requests to a blocking cache port.
// A redirect discards the old response; the newest requested PC is retained
// while an earlier cache fill finishes.
module imem_cache_adapter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    input  wire        core_req,
    input  wire [31:0] core_addr,
    output wire [31:0] core_rdata,
    output wire        core_ready,
    output wire        cache_req,
    output wire [31:0] cache_addr,
    input  wire [31:0] cache_rdata,
    input  wire        cache_ready
);
    reg wanted_valid, active;
    reg [31:0] wanted_addr, active_addr;
    // The core discards a response on the same edge as a redirect. Keeping
    // flush off ready avoids a long EX-target -> fetch-ready -> register-enable
    // path while the sequential flush still drops the stale wanted address.
    wire current_response = active && cache_ready && wanted_valid &&
                            wanted_addr == active_addr;
    assign core_ready = current_response;
    assign core_rdata = cache_rdata;
    // wanted_addr is already registered. Let the cache accept it on the
    // same edge that sets active, rather than inserting another idle cycle.
    // Once accepted, hold active_addr until the blocking response returns.
    // A flush can still launch a harmless stale request; wanted_valid and
    // the address comparison above prevent that response reaching the CPU.
    assign cache_req = active || wanted_valid;
    assign cache_addr = active ? active_addr : wanted_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wanted_valid <= 1'b0;
            wanted_addr <= 0;
            active <= 1'b0;
            active_addr <= 0;
        end else begin
            if (active && cache_ready) active <= 1'b0;
            else if (!active && wanted_valid) begin
                active <= 1'b1;
                active_addr <= wanted_addr;
            end
            if (flush) wanted_valid <= 1'b0;
            else if (core_req) begin
                wanted_valid <= 1'b1;
            end else if (current_response) wanted_valid <= 1'b0;
            // Address data is ignored while wanted_valid is clear. Capture
            // independently so redirect logic does not drive 32 data CEs.
            if (core_req) wanted_addr <= core_addr;
        end
    end
endmodule
