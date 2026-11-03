`timescale 1ns/1ps
// Independent electrical I2C fixture: only sees SCL/SDA and a simulation epoch.
// Expected bytes are the existing independently transcribed vendor table.
module q_tx_wire_slave(input wire scl,reset_n,ack_enable,inout wire sda,
    output integer starts=0,stops=0,bytes=0);
    reg slave_low=0,active=0;
    integer bits=0,transaction_bytes=0,command_number=0;
    reg [7:0] shift=0,received=0;
    reg [7:0] expected[0:195];reg [2047:0] reference_path;integer fd;
    assign sda=slave_low?1'b0:1'bz;
    initial begin
        if(!$value$plusargs("ms7210_reference=%s",reference_path))$fatal(1,"missing vendor reference argument");
        fd=$fopen(reference_path,"r");if(!fd)$fatal(1,"missing vendor reference file");$fclose(fd);
        $readmemh(reference_path,expected);
    end
    always @(negedge reset_n)begin
        starts=0;stops=0;bytes=0;bits=0;transaction_bytes=0;command_number=0;active=0;slave_low=0;
    end
    always @(negedge sda)if(scl&&reset_n)begin
        if(active)$fatal(1,"unexpected TX repeated START");
        active=1;bits=0;transaction_bytes=0;starts=starts+1;
    end
    always @(posedge sda)if(scl&&reset_n&&active)begin
        active=0;stops=stops+1;
        if(ack_enable&&transaction_bytes!=4)$fatal(1,"TX STOP before complete4-byte write");
        if(transaction_bytes==4)command_number=command_number+1;
    end
    always @(posedge scl)if(active&&transaction_bytes<4)begin
        if(bits<8)begin
            received={shift[6:0],sda};shift=received;
            if(bits==7 && (command_number>=49||received!==expected[command_number*4+transaction_bytes]))
                $fatal(1,"TX wire reference mismatch cmd%0d byte%0d value%h",command_number,transaction_bytes,received);
            bits=bits+1;
        end else begin bits=0;bytes=bytes+1;transaction_bytes=transaction_bytes+1;end
    end
    always @(negedge scl)if(active)slave_low=(bits==8&&ack_enable);else slave_low=0;
endmodule

module tb_status_out;
    reg sys_clk=0,rx_clk=0,rx_run=0,sys_pll_ready=0;
    always #10 sys_clk=~sys_clk;
    always #3.367 if(rx_run)rx_clk=~rx_clk;
    reg rx_de=0,rx_hs=0,rx_vs=0;reg [23:0] rx_rgb=0;
    reg [7:0] status_code=8'h82;
    tri1 rx_sda,tx_sda;wire rx_scl,hdmi_rst_n,tx_scl,pclk,hs,vs,de;
    wire [7:0] r,g,b;wire [26:0] capture_sample;wire capture_ready,capture_reset_n,diag_reset_n;wire [511:0] diag;
    hdmi_capture_frontend #(.GEO_INTERVAL_CYCLES(1000),.EXPECT_W(16),.EXPECT_H(8),.EXPECT_HTOTAL(64),.EXPECT_VTOTAL(16)) dut(
        .sys_clk(sys_clk),.status_code(status_code),.sys_pll_ready(sys_pll_ready),
        .hdmi_rx_pixclk(rx_clk),.hdmi_rx_de(rx_de),.hdmi_rx_hs(rx_hs),.hdmi_rx_vs(rx_vs),
        .hdmi_rx_r(rx_rgb[23:16]),.hdmi_rx_g(rx_rgb[15:8]),.hdmi_rx_b(rx_rgb[7:0]),
        .hdmi_rx_iic_scl(rx_scl),.hdmi_rx_iic_sda(rx_sda),.hdmi_rst_n(hdmi_rst_n),.hdmi_scl(tx_scl),.hdmi_sda(tx_sda),
        .hdmi_pclk(pclk),.hdmi_hs(hs),.hdmi_vs(vs),.hdmi_de(de),.hdmi_r(r),.hdmi_g(g),.hdmi_b(b),
        .capture_sample(capture_sample),.capture_ready(capture_ready),.capture_reset_n(capture_reset_n),.diag_reset_n(diag_reset_n),.diag_source(diag));
    // Speed up waits only. Formal pixel timing remains actual SYS50/25MHz.
    defparam dut.por.COUNTER_BITS=4;
    defparam dut.u_hdmi_init.QUARTER_CYCLES=2,dut.u_hdmi_init.RESET_CYCLES=4,
             dut.u_hdmi_init.WRITE_GAP_CYCLES=2,dut.u_hdmi_init.SETTLE_CYCLES=6;
    defparam dut.rx.Q=2,dut.rx.BOOT_WAIT=4,dut.rx.GAP=2,dut.rx.POLL_WAIT=16;
    defparam dut.geometry.TIMEOUT_CYCLES=2000;
    defparam dut.live_input.FREQ_TTL=2000,dut.live_input.GEO_TTL=10000;
    reg ack_enable=1;
    wire [31:0] tx_starts,tx_stops,tx_bytes;
    q_tx_wire_slave tx_fixture(.scl(tx_scl),.sda(tx_sda),.reset_n(dut.tx_software_reset_n),.ack_enable(ack_enable),
        .starts(tx_starts),.stops(tx_stops),.bytes(tx_bytes));
    reg physical_released=0;
    always @(posedge hdmi_rst_n)physical_released=1;
    always @(negedge hdmi_rst_n)if(physical_released)$fatal(1,"TX software reset pulsed shared RX physical reset");
    integer pixel_edges=0,sampler_checks=0;time last_pclk=0;
    reg [26:0] at_rise=0,last_half_sample=0;reg at_rise_valid=0;
    always @(pclk)begin
        if(last_pclk!=0 && $time-last_pclk!=20)$fatal(1,"PCLK not continuous SYS/2");
        last_pclk=$time;
    end
    always @(posedge pclk)begin
        #1;pixel_edges=pixel_edges+1;at_rise={hs,vs,de,r,g,b};at_rise_valid=dut.status_video_ready;
        if(dut.status_video_ready&&!de&&{r,g,b}!==24'b0)$fatal(1,"RGB leaked outside DE");
    end
    always @(negedge pclk)begin
        #1;if(at_rise_valid&&dut.status_video_ready&&{hs,vs,de,r,g,b}!==at_rise)$fatal(1,"OUT changed at opposite sampling edge");
    end
    always @(negedge rx_clk)begin #0.01;last_half_sample={rx_hs,rx_vs,rx_de,rx_rgb};end
    always @(posedge rx_clk)begin
        #0.02;if(dut.rst_n)begin
            if(capture_sample!==last_half_sample)$fatal(1,"J falling-half/rising capture contract changed");
            sampler_checks=sampler_checks+1;
        end
    end
    always @(negedge sys_clk)begin #0.05;if(dut.rst_n)begin
        if(capture_reset_n!==capture_ready)$fatal(1,"capture epoch reset detached from original ready");
        if(capture_ready !== (dut.rst_n&&dut.rx_ready&&dut.video_enable&&dut.tx_done&&!dut.tx_error&&dut.input_online))
            $fatal(1,"capture admission changed");
        if(diag[31:0]!==32'h48303451||!diag[48]||diag[63:52]!==0)$fatal(1,"Q payload identity/ABI flags");
        if(diag[51:49]!=={dut.status_video_ready,dut.tx_software_reset_n,sys_pll_ready})$fatal(1,"Q OUT flags inaccurate");
        if(!dut.status_video_ready&&{hs,vs,de,r,g,b}!=={1'b1,1'b1,1'b0,24'b0})$fatal(1,"video not held reset on TX failure/PLL loss");
    end end
    task frame_check;
        input [23:0] bar;integer n,active_count,hs_count,vs_count,bar_count,digits;
        begin
            @(negedge vs);active_count=0;hs_count=0;vs_count=0;bar_count=0;digits=0;
            for(n=0;n<800*525;n=n+1)begin
                @(posedge pclk);#1;
                if(de)active_count=active_count+1;
                if(!hs)hs_count=hs_count+1;
                if(!vs)vs_count=vs_count+1;
                if(de&&{r,g,b}==bar)bar_count=bar_count+1;
                if(de&&{r,g,b}==24'he8f4ff)digits=digits+1;
            end
            if(active_count!=640*480||hs_count!=96*525||vs_count!=2*800||bar_count!=96*640||digits<100)
                $fatal(1,"status geometry/color active%0d hs%0d vs%0d bar%0d digits%0d",active_count,hs_count,vs_count,bar_count,digits);
            $display("Q_NO_IN_STATUS_FRAME_PASS active=%0d hs=%0d vs=%0d bar=%0d digits=%0d",active_count,hs_count,vs_count,bar_count,digits);
        end
    endtask
    reg inject_fixture=0;reg [31:0] fixture_sample=32'h00020000,fixture_poll=0;reg fixture_update=0;
    integer frequency_div=0;
    always @(negedge sys_clk)begin
        fixture_update=0;
        if(inject_fixture)begin
            if(frequency_div==127)begin frequency_div=0;fixture_update=1;fixture_poll=fixture_poll+1;end
            else frequency_div=frequency_div+1;
        end
    end
    integer x=0,y=0,xx,yy;
    always @(posedge rx_clk)begin
        #0.1;
        rx_hs=x<4;rx_vs=y<2;rx_de=x>=12&&x<28&&y>=5&&y<13;
        xx=x-12;yy=y-5;rx_rgb={8'(xx*7+yy*3+23),8'(xx*11+yy*5+106),8'(xx*13+yy*17+190)};
        if(x==63)begin x=0;if(y==15)y=0;else y=y+1;end else x=x+1;
    end
    task wait_ready;
        integer n;
        begin
            n=0;while(!capture_ready&&n<30000)begin @(negedge sys_clk);n=n+1;end
            if(!capture_ready)$fatal(1,"valid documented state2 failed original qualification reason%h",dut.online_reason);
        end
    endtask
    integer edge_before,n;reg saw_red=0;
    initial begin
        wait(hdmi_rst_n);repeat(8)@(negedge sys_clk);
        if(tx_starts!=0||capture_ready)$fatal(1,"TX started without SYS PLLready");
        sys_pll_ready=1;wait(dut.tx_done||dut.tx_error);#1;
        if(dut.tx_error||tx_starts!=49||tx_stops!=49||tx_bytes!=196||dut.tx_release||capture_ready)
            $fatal(1,"no-IN TX independent init failed %0d/%0d/%0d",tx_starts,tx_stops,tx_bytes);
        frame_check(24'h186843);
        status_code=8'hff;repeat(4)@(negedge sys_clk);
        n=0;while(!saw_red&&n<800*525)begin @(posedge pclk);#1;if(de&&{r,g,b}==24'h8c2830)saw_red=1;n=n+1;end
        if(!saw_red)$fatal(1,"GPIO status_code did not change status page");
        $display("Q_GPIO_STATUS_CODE_FF_RED_PASS");status_code=8'h82;
        // Named RX-I2C boundary fixture only; real sampler/geometry/startup/
        // qualification/epoch remain live. TX done/error are never forced.
        force dut.rx_init=1;force dut.edid_ok=1;force dut.setting_done=1;force dut.fault=0;
        force dut.frequency_sample=fixture_sample;force dut.frequency_update=fixture_update;force dut.poll_sequence=fixture_poll;
        inject_fixture=1;rx_run=1;wait_ready;
        if(!dut.video_enable||sampler_checks<100)$fatal(1,"real RX geometry/video or sampler not exercised");
        $display("Q_CAPTURE_READY_TIMING original_boolean_gate=1 startup_tx_release_at_ready=%0d",dut.tx_release);
        // Original startup TX-release indication is only latched after four
        // fresh geometries; Q does not use it to gate independent TX init.
        n=0;while(!dut.tx_release&&n<30000)begin @(negedge sys_clk);n=n+1;end
        if(!dut.tx_release)$fatal(1,"original RX startup indication never completed");
        $display("Q_IN_STATE2_CAPTURE_PASS sampler_checks=%0d geo_samples=%0d",sampler_checks,dut.geo_samples);
        fixture_sample=32'h00035800;repeat(256)@(negedge sys_clk);
        for(n=0;n<3000;n=n+1)begin @(negedge sys_clk);if(capture_ready||dut.input_online)$fatal(1,"unknown RX state3 admitted");end
        $display("Q_UNKNOWN_STATE3_REJECT_PASS");
        fixture_sample=32'h00020000;wait_ready;
        @(negedge rx_clk);#1;rx_run=0;edge_before=pixel_edges;
        repeat(7000)@(negedge sys_clk);
        if(capture_ready||dut.input_online||pixel_edges-edge_before<3000||!dut.tx_done||tx_starts!=49)
            $fatal(1,"IN loss disturbed independent OUT or failed epoch cancel");
        $display("Q_RX_CLOCK_LOSS_STATUS_CONTINUES_PASS");
        // SYS PLL loss/retry affects TX software only, never shared R17/RX.
        sys_pll_ready=0;repeat(8)@(negedge sys_clk);ack_enable=0;sys_pll_ready=1;
        wait(dut.tx_error||dut.tx_done);repeat(3)@(negedge sys_clk);
        if(!dut.tx_error||dut.tx_done||capture_ready||dut.status_video_ready||tx_starts!=1||tx_stops!=1||tx_bytes!=1||!hdmi_rst_n)
            $fatal(1,"TX NACK not retained as failure");
        $display("Q_TX_NACK_FAIL_CLOSED_PASS starts=%0d stops=%0d bytes=%0d",tx_starts,tx_stops,tx_bytes);
        sys_pll_ready=0;repeat(8)@(negedge sys_clk);ack_enable=1;sys_pll_ready=1;
        wait(dut.tx_done||dut.tx_error);repeat(8)@(negedge sys_clk);
        if(dut.tx_error||!dut.status_video_ready||tx_starts!=49||tx_stops!=49||capture_ready||!hdmi_rst_n||dut.u_hdmi_video.code_sync!=8'h82)
            $fatal(1,"TX software recovery/RX isolation failed");
        $display("Q_PLL_SOFTWARE_RESET_NO_PHYSICAL_RX_RESET_PASS");
        $display("H04Q_FRONTEND_INDEPENDENT_STATUS_OUT_PASS no_IN_real49_I2C full640x480 GPIO IN_loss state3_reject NACK software_retry single_POR_owner");$finish;
    end
    initial begin #45000000;$fatal(1,"Q frontend timeout");end
endmodule
