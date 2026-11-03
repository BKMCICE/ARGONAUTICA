// rv_btb.v - Direct-mapped Branch Target Buffer with 2-bit saturating counters.
// Lookup is combinational on the fetch PC; update comes from MEM when a
// branch commits.
module rv_btb #(
    parameter ENTRIES = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] lookup_pc,
    output wire        hit,          // valid entry, tag match, predict taken
    output wire [31:0] target,
    input  wire        update,
    input  wire [31:0] update_pc,
    input  wire        update_taken,
    input  wire [31:0] update_target
);
    localparam IDXW = $clog2(ENTRIES);
    localparam TAGW = 30 - IDXW;

    reg              valid_r [0:ENTRIES-1];
    reg  [TAGW-1:0]  tag_r   [0:ENTRIES-1];
    reg  [31:0]      tgt_r   [0:ENTRIES-1];
    reg  [1:0]       ctr_r   [0:ENTRIES-1];

    wire [IDXW-1:0] l_idx = lookup_pc[IDXW+1:2];
    wire [TAGW-1:0] l_tag = lookup_pc[31:IDXW+2];
    wire [IDXW-1:0] u_idx = update_pc[IDXW+1:2];
    wire [TAGW-1:0] u_tag = update_pc[31:IDXW+2];

    assign hit    = valid_r[l_idx] && (tag_r[l_idx] == l_tag) && ctr_r[l_idx][1];
    assign target = tgt_r[l_idx];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                valid_r[i] <= 1'b0; tag_r[i] <= 0; tgt_r[i] <= 0; ctr_r[i] <= 2'b01;
            end
        end else if (update) begin
            if (valid_r[u_idx] && tag_r[u_idx] == u_tag) begin
                // same branch: train counter
                if (update_taken) begin
                    if (ctr_r[u_idx] != 2'b11) ctr_r[u_idx] <= ctr_r[u_idx] + 2'b01;
                    tgt_r[u_idx] <= update_target;
                end else begin
                    if (ctr_r[u_idx] != 2'b00) ctr_r[u_idx] <= ctr_r[u_idx] - 2'b01;
                end
            end else if (update_taken) begin
                // allocate on taken branch only
                valid_r[u_idx] <= 1'b1;
                tag_r[u_idx]   <= u_tag;
                tgt_r[u_idx]   <= update_target;
                ctr_r[u_idx]   <= 2'b10;
            end
        end
    end
endmodule
