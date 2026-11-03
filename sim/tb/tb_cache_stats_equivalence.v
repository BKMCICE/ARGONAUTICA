`timescale 1ns/1ps
// Frozen pre-A35 reference is supplied separately by the validation runner.
module tb_cache_stats_equivalence;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, req = 0, we = 0;
    reg [3:0] be = 0, events = 0;
    reg [31:0] addr = 0, wdata = 0;
    wire [31:0] original_read, default_read, split_read;
    wire original_ready, default_ready, split_ready;
    cache_stats_reference reference(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),
        .addr(addr),.wdata(wdata),.rdata(original_read),.ready(original_ready),
        .i_hit(events[3]),.i_miss(events[2]),.d_hit(events[1]),.d_miss(events[0]));
    cache_stats default_dut(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),
        .addr(addr),.wdata(wdata),.rdata(default_read),.ready(default_ready),
        .i_hit(events[3]),.i_miss(events[2]),.d_hit(events[1]),.d_miss(events[0]));
    cache_stats #(.SPLIT_COUNTERS(1)) split_dut(.clk(clk),.rst_n(rst_n),.req(req),.we(we),.be(be),
        .addr(addr),.wdata(wdata),.rdata(split_read),.ready(split_ready),
        .i_hit(events[3]),.i_miss(events[2]),.d_hit(events[1]),.d_miss(events[0]));
    reg enabled = 1;
    reg [3:0] queued = 0;
    reg [31:0] model [0:3];
    integer i, j, checked = 0;
    reg [31:0] random_state = 32'h35cafe01;
    task random_next;
        begin
            random_state = random_state ^ (random_state << 13);
            random_state = random_state ^ (random_state >> 17);
            random_state = random_state ^ (random_state << 5);
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled = 1;
            queued = 0;
            for (integer k=0;k<4;k=k+1) model[k] = 0;
        end else begin
            if (req && we && addr[4:2]==0 && wdata[1]) begin
                for (integer k=0;k<4;k=k+1) model[k] = 0;
                queued = 0;
            end else begin
                for (integer k=0;k<4;k=k+1)
                    model[k] = model[k] + (queued[3-k] ? 32'd1 : 32'd0);
                queued = enabled ? events : 0;
            end
            if (req && we && addr[4:2]==0) enabled = wdata[0];
        end
    end
    task check;
        reg [31:0] expected;
        begin
            case (addr[4:2])
                0: expected = {31'b0,enabled};
                1: expected = model[0];
                2: expected = model[1];
                3: expected = model[2];
                4: expected = model[3];
                default: expected = 0;
            endcase
            if ({original_ready,default_ready,split_ready} !== 3'b111 ||
                original_read !== expected || default_read !== expected || split_read !== expected)
                $fatal(1,"A35 mismatch cycle=%0d addr=%h expected=%h old=%h default=%h split=%h",checked,addr,expected,original_read,default_read,split_read);
            if ({reference.ihits,reference.imisses,reference.dhits,reference.dmisses} !==
                {model[0],model[1],model[2],model[3]} ||
                {default_dut.ihits,default_dut.imisses,default_dut.dhits,default_dut.dmisses} !==
                {model[0],model[1],model[2],model[3]} ||
                {split_dut.ihits,split_dut.imisses,split_dut.dhits,split_dut.dmisses} !==
                {model[0],model[1],model[2],model[3]})
                $fatal(1,"A35 internal counters differ from independent scoreboard");
            checked = checked + 1;
        end
    endtask
    task tick;
        begin @(posedge clk); #1; check(); end
    endtask
    task seed_counts;
        input [31:0] value;
        begin
            // Verification-only deposits cover carry/wrap without 2^32 clocks.
            // No force persists: every following update is performed by RTL.
            reference.ihits=value; reference.imisses=value; reference.dhits=value; reference.dmisses=value;
            default_dut.ihits=value; default_dut.imisses=value; default_dut.dhits=value; default_dut.dmisses=value;
            split_dut.ihits=value; split_dut.imisses=value; split_dut.dhits=value; split_dut.dmisses=value;
            for (integer k=0;k<4;k=k+1) model[k]=value;
        end
    endtask
    initial begin
        for (i=0;i<4;i=i+1) model[i]=0;
        #1; rst_n=1; #1; rst_n=0; #1; check(); #1; rst_n=1;
        // Every four-event mask at every old control value; repeated writes,
        // clear discards queued/concurrent events, and enable uses old value.
        for (i=0;i<16;i=i+1) begin
            for (j=0;j<4;j=j+1) begin
                @(negedge clk); events=i; req=0; we=0; tick();
                @(negedge clk); req=1; we=1; addr=0; wdata=j; be=i; tick();
                @(negedge clk); req=0; we=0; tick();
            end
        end
        @(negedge clk); req=1; we=1; addr=0; wdata=1; events=0; tick();
        @(negedge clk); req=0; we=0; tick();
        for (i=0;i<4;i=i+1) begin
            @(negedge clk); events=0;
            case(i)
                0: seed_counts(32'h000000fe);
                1: seed_counts(32'h0000fffe);
                2: seed_counts(32'h00fffffe);
                3: seed_counts(32'hfffffffe);
            endcase
            // Eight consecutive all-channel events cross each boundary.
            for (j=0;j<8;j=j+1) begin events=15; tick(); @(negedge clk); end
            events=0; tick();
        end
        for (i=0;i<25000;i=i+1) begin
            @(negedge clk);
            random_next(); events=random_state[3:0]; req=random_state[4]; we=random_state[5]; be=random_state[9:6];
            random_next(); addr=random_state;
            // Exercise control often while retaining high/low alias bits.
            if (i%3==0) addr[4:2]=0;
            random_next(); wdata=random_state;
            if (i%701==0) begin rst_n=0; #1; check(); end
            if (i%701==1) rst_n=1;
            #1; check(); tick();
        end
        $display("A35_CACHE_STATS_EQUIVALENCE_PASS checks=%0d random_cycles=25000 carry_boundaries=8,16,24,32 ready=1",checked);
        $finish;
    end
endmodule
