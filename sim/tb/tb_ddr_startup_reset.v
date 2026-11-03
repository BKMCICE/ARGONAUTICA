`timescale 1ns/1ps
// Exercise the actual POR and the two synchronizers used by ddr3_test with
// a stopped UI clock, delayed PHY startup, and asynchronous reset reassertion.
module tb_ddr_startup_reset;
    reg ref_clk = 0, ui_clk = 0, ui_running = 0, external_n = 1;
    always #10 ref_clk = ~ref_clk;
    always #5 if (ui_running) ui_clk = ~ui_clk;
    wire por_n, phy_n, mc_n;
    power_on_reset #(.COUNTER_BITS(3)) por (.clk(ref_clk), .rst_n(por_n));
    ipsxb_rst_sync_v1_1 phy_sync (.clk(ref_clk), .rst_n(por_n && external_n),
        .sig_async(1'b1), .sig_synced(phy_n));
    ipsxb_rst_sync_v1_1 mc_sync (.clk(ui_clk), .rst_n(phy_n),
        .sig_async(1'b1), .sig_synced(mc_n));
    integer n;
    initial begin
        #1;
        if (por_n !== 0) $fatal(1,"initial POR missing");
        for (n=1; n<=6; n=n+1) begin
            @(posedge ref_clk); #1;
            if (por_n !== 0) $fatal(1,"POR released too early");
            if (n >= 2 && mc_n !== 0) $fatal(1,"UI reset not asserted by reference reset");
        end
        @(posedge ref_clk); #1;
        if (por_n !== 1) $fatal(1,"POR did not expire");
        repeat (12) @(posedge ref_clk);
        #1;
        if (phy_n !== 1 || mc_n !== 0) $fatal(1,"UI reset released without UI clock");
        ui_running = 1;
        @(posedge ui_clk); #1;
        if (mc_n !== 0) $fatal(1,"UI reset released on first edge");
        @(posedge ui_clk); #1;
        if (mc_n !== 1) $fatal(1,"UI reset did not release on second edge");
        #2 external_n = 0; #1;
        if (phy_n !== 0 || mc_n !== 0) $fatal(1,"reset assertion is not asynchronous");
        @(negedge ref_clk); external_n = 1;
        wait (phy_n === 1);
        @(posedge ui_clk); #1;
        if (mc_n !== 0) $fatal(1,"reset recovery skipped first UI edge");
        @(posedge ui_clk); #1;
        if (mc_n !== 1) $fatal(1,"reset recovery failed");
        repeat (20) @(posedge ref_clk);
        if (por_n !== 1) $fatal(1,"POR counter wrapped");
        $display("DDR_RESET_PASS stopped_ui=1 delayed_start=1 reassert=1 saturates=1");
        $finish;
    end
    initial begin #3000; $fatal(1,"reset test timeout"); end
endmodule
