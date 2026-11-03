// Simulation-only 64 KiB backing memory with a 32-byte line-transfer port.
// A transaction takes four cycles; the port models a native burst beat.
module burst_ram_model (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         req,
    input  wire         we,
    input  wire [31:0]  addr,
    input  wire [255:0] wdata,
    output reg  [255:0] rdata,
    output wire         ready
);
    reg [31:0] mem [0:16383];
    reg active;
    reg [2:0] remaining;
    reg [31:0] held_addr;
    reg [255:0] held_wdata;
    reg held_we;
    reg [1023:0] hexfile;
    integer i;
    initial begin
        for (i = 0; i < 16384; i = i + 1) mem[i] = 32'h0000_0013;
        if (!$value$plusargs("hex=%s", hexfile)) hexfile = "prog.hex";
        $readmemh(hexfile, mem);
    end

    assign ready = active && remaining == 0;
    integer j;
    always @(*) begin
        rdata = 0;
        for (integer k = 0; k < 8; k = k + 1)
            if ((held_addr[31:2] + k) < 16384)
                rdata[k*32 +: 32] = mem[held_addr[15:2] + k];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 0;
            remaining <= 0;
            held_addr <= 0;
            held_wdata <= 0;
            held_we <= 0;
        end else if (!active && req) begin
            active <= 1;
            remaining <= 3;
            held_addr <= addr;
            held_wdata <= wdata;
            held_we <= we;
        end else if (active && remaining != 0) begin
            remaining <= remaining - 1;
        end else if (ready) begin
            if (held_we)
                for (j = 0; j < 8; j = j + 1)
                    if ((held_addr[31:2] + j) < 16384)
                        mem[held_addr[15:2] + j] <= held_wdata[j*32 +: 32];
            active <= 0;
        end
    end
endmodule
