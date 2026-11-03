// H04T private observed-input qualification with reset-separated geometry epochs.
// SYS50/CE2 status video and ACK-only formal TX initialization are independent of IN.
// One SoC UART only: no ROI console and no second UART driver in this module.
module hdmi_capture_frontend #(
    parameter integer GEO_INTERVAL_CYCLES=50000,
    parameter integer QUAL_OBS_TTL=10000000,QUAL_GEO_START_TTL=5000000,QUAL_GEO_TTL=2500000,QUAL_RESET_HOLD_CYCLES=8,
    parameter integer ENABLE_RESULT_UI=0,
    parameter integer EXPECT_W=1920,EXPECT_H=1080,EXPECT_HTOTAL=2200,EXPECT_VTOTAL=1125
)(
    input wire sys_clk,hdmi_rx_pixclk,hdmi_rx_de,hdmi_rx_hs,hdmi_rx_vs,
    input wire [7:0] status_code,
    input wire result_valid,input wire [2:0] result_phase,input wire [7:0] result_count,
    input wire [31:0] result_ms,input wire [79:0] result_classes,input wire [99:0] result_scores,
    input wire sys_pll_ready,
    input wire [7:0] hdmi_rx_r,hdmi_rx_g,hdmi_rx_b,
    output wire hdmi_rx_iic_scl,inout wire hdmi_rx_iic_sda,
    output wire hdmi_rst_n,hdmi_scl,inout wire hdmi_sda,
    output wire hdmi_pclk,hdmi_vs,hdmi_hs,hdmi_de,
    output wire [7:0] hdmi_r,hdmi_g,hdmi_b,
    output reg [26:0] capture_sample=0,
    output wire capture_ready,capture_reset_n,
    output wire diag_reset_n,output wire [511:0] diag_source
);
    wire rst_n,rx_init,edid_ok,setting_done;
    wire [3:0] fault;
    wire [7:0] phase_before,phase_after,fault_actual,fault_expected;
    wire [15:0] fault_address,debug_progress;
    wire [31:0] frequency_status,frequency_sample,poll_sequence;
    wire frequency_update;
    wire observation_valid,last_observation_error,observation_busy;
    wire [31:0] observation_raw,observation_sequence,observation_age;
    power_on_reset por(.clk(sys_clk),.rst_n(rst_n));
    hdmi_capture_rx_control rx(.clk(sys_clk),.rst_n(rst_n),.scl(hdmi_rx_iic_scl),.sda(hdmi_rx_iic_sda),
        .initialized(rx_init),.edid_ok(edid_ok),.setting_done(setting_done),.fault(fault),
        .fault_address(fault_address),.fault_actual(fault_actual),.fault_expected(fault_expected),.frequency_status(frequency_status),
        .phase_before(phase_before),.phase_after(phase_after),.frequency_update(frequency_update),
        .frequency_sample(frequency_sample),.poll_sequence(poll_sequence),.debug_progress(debug_progress),
        .observation_valid(observation_valid),.last_observation_error(last_observation_error),.observation_busy(observation_busy),
        .observation_raw(observation_raw),.observation_sequence(observation_sequence),.observation_age(observation_age));
    wire rx_ready=rx_init&&edid_ok&&setting_done&&(fault==0);
    wire geo_busy,geo_valid,geo_timeout,video_enable,tx_release,tx_done,tx_error;
    wire [175:0] snapshot;
    wire geometry_reset_n;wire [31:0] qualification_epoch;
    (* syn_preserve=1 *) reg [31:0] geo_epoch=0;
    (* syn_preserve=1,async_reg="true" *) reg [1:0] geo_release=0;
    always @(posedge sys_clk or negedge geometry_reset_n)
        if(!geometry_reset_n)geo_release<=0;else geo_release<={geo_release[0],1'b1};
    wire geometry_run_n=geo_release[1];
    reg [31:0] interval=0;reg geo_request=0;
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n)begin interval<=0;geo_request<=0;geo_epoch<=0;end
        else begin
            geo_request<=0;
            if(!geometry_run_n)begin interval<=0;geo_epoch<=qualification_epoch;end
            else begin
                if(geo_request&&!geo_busy)geo_epoch<=qualification_epoch;
                if(interval==GEO_INTERVAL_CYCLES-1)begin
                    interval<=0;if(!geo_busy)geo_request<=1;
                end else interval<=interval+1'b1;
            end
        end
    end
    hdmi_rx_geometry geometry(.sys_clk(sys_clk),.pix_clk(hdmi_rx_pixclk),.rst_n(geometry_run_n),
        .de(capture_sample[24]),.hs(capture_sample[26]),.vs(capture_sample[25]),
        .request(geo_request),.busy(geo_busy),.valid(geo_valid),.timed_out(geo_timeout),.snapshot(snapshot));
    hdmi_video_first_start startup(.clk(sys_clk),.rst_n(geometry_run_n),.rx_ready(rx_ready),
        .valid(geo_valid),.timed_out(geo_timeout),.snapshot(snapshot),
        .video_enable(video_enable),.tx_release(tx_release),.stable_count());
    // Shared R17 has exactly one owner: global POR. TX software reset and
    // its internal RESET phase must never assert the RX physical reset again.
    assign hdmi_rst_n=rst_n;
    wire tx_software_reset_n=rst_n&&sys_pll_ready;
    wire status_video_ready=tx_software_reset_n&&tx_done&&!tx_error;
    ms7210_init u_hdmi_init(.clk(sys_clk),.rst_n(tx_software_reset_n),
        .hdmi_rst_n(),.scl(hdmi_scl),.sda(hdmi_sda),
        .init_done(tx_done),.init_error(tx_error));
    // Same SYS50/CE2 relationship as formal A61; never an internal fabric clock.
    (* syn_preserve=1 *) reg hdmi_pix_phase=0;
    always @(posedge sys_clk)hdmi_pix_phase<=~hdmi_pix_phase;
    assign hdmi_pclk=hdmi_pix_phase;
    wire legacy_hs,legacy_vs,legacy_de;
    wire [7:0] legacy_r,legacy_g,legacy_b;
    hdmi_status_video u_hdmi_video(.pix_clk(sys_clk),.pixel_enable(!hdmi_pix_phase),
        .rst_n(status_video_ready),.status_code(status_code),
        .hs(legacy_hs),.vs(legacy_vs),.de(legacy_de),.r(legacy_r),.g(legacy_g),.b(legacy_b));
    generate if(ENABLE_RESULT_UI)begin: result_page
        wire next_frame,result_hs,result_vs,result_de;
        wire [7:0] result_r,result_g,result_b;
        reg selected=0;
        always @(posedge sys_clk or negedge status_video_ready)
            if(!status_video_ready)selected<=0;else if(next_frame)selected<=result_valid;
        hdmi_result_video u_hdmi_result_video(.pix_clk(sys_clk),.pixel_enable(!hdmi_pix_phase),
            .rst_n(status_video_ready),.status_code(status_code),.result_valid(result_valid),
            .phase(result_phase),.count(result_count),.forward_ms(result_ms),
            .classes(result_classes),.scores(result_scores),.frame_start(next_frame),
            .hs(result_hs),.vs(result_vs),.de(result_de),.r(result_r),.g(result_g),.b(result_b));
        assign {hdmi_hs,hdmi_vs,hdmi_de,hdmi_r,hdmi_g,hdmi_b}=selected ?
            {result_hs,result_vs,result_de,result_r,result_g,result_b} :
            {legacy_hs,legacy_vs,legacy_de,legacy_r,legacy_g,legacy_b};
    end else begin: legacy_page
        assign {hdmi_hs,hdmi_vs,hdmi_de,hdmi_r,hdmi_g,hdmi_b}=
            {legacy_hs,legacy_vs,legacy_de,legacy_r,legacy_g,legacy_b};
    end endgenerate
    wire [26:0] half_sample;
    hdmi_rgb_loop pixels(.pix_clk(hdmi_rx_pixclk),.rst_n(rst_n),.enable(1'b1),
        .in_hs(hdmi_rx_hs),.in_vs(hdmi_rx_vs),.in_de(hdmi_rx_de),.in_rgb({hdmi_rx_r,hdmi_rx_g,hdmi_rx_b}),
        .out_clk(),.capture_sample(half_sample),
        .out_hs(),.out_vs(),.out_de(),.out_rgb());
    always @(posedge hdmi_rx_pixclk or negedge rst_n)
        if(!rst_n)capture_sample<=0;else capture_sample<=half_sample;
    wire input_online;wire [31:0] online_reason,geometry_age;
    hdmi_observed_qualification #(.W(EXPECT_W),.H(EXPECT_H),.HTOTAL(EXPECT_HTOTAL),.VTOTAL(EXPECT_VTOTAL),
        .OBS_TTL(QUAL_OBS_TTL),.GEO_START_TTL(QUAL_GEO_START_TTL),.GEO_TTL(QUAL_GEO_TTL),.RESET_HOLD_CYCLES(QUAL_RESET_HOLD_CYCLES)) live_input(
        .clk(sys_clk),.rst_n(rst_n),.rx_ready(rx_ready),.tx_error(tx_error),
        .observation_valid(observation_valid),.last_observation_error(last_observation_error),.observation_busy(observation_busy),
        .observation_raw(observation_raw),.observation_sequence(observation_sequence),.observation_age(observation_age),
        .geo_valid(geo_valid),.geo_timeout(geo_timeout),.geometry(snapshot),.geo_epoch(geo_epoch),
        .online(input_online),.geometry_reset_n(geometry_reset_n),.epoch(qualification_epoch),.reason(online_reason),.geometry_age(geometry_age));
    assign capture_ready=rst_n&&rx_ready&&video_enable&&tx_done&&!tx_error&&input_online;
    // Shared epoch reset is asserted on source qualification loss, then FIFO
    // domains release locally. Never reset native writer/DDR on source loss.
    assign capture_reset_n=capture_ready;
    reg [31:0] geo_samples=0;
    always @(posedge sys_clk or negedge rst_n)
        if(!rst_n)geo_samples<=0;else if(geo_valid)geo_samples<=geo_samples+1'b1;
    assign diag_reset_n=rst_n;
    // T payload ABI: MMIO transport ID at0x20 remains H04I.
    // Bit3 is ACK-only49-write initialization, never PLL/HPD/frequency readback.
    // Bit9 remains the RX startup indicator and no longer releases the TX.
    assign diag_source[0*32+:32]=32'h48303454;
    // Bits19:0 retain Q semantics. New20valid/21last_error/22busy;31:23zero.
    // T admission uses documented observations plus new complete geometry; old frequency is diagnostic only.
    assign diag_source[1*32+:32]={9'b0,observation_busy,last_observation_error,observation_valid,status_video_ready,tx_software_reset_n,sys_pll_ready,1'b1,fault,capture_ready,input_online,tx_release,video_enable,
        geo_timeout,geo_valid,geo_busy,tx_error,tx_done,setting_done,edid_ok,rx_init};
    assign diag_source[2*32+:32]=frequency_sample;
    assign diag_source[3*32+:32]=qualification_epoch;
    assign diag_source[4*32+:32]={fault_address,fault_actual,fault_expected};
    assign diag_source[5*32+:32]={debug_progress,phase_before,phase_after};
    assign diag_source[6*32+:32]=observation_raw;
    assign diag_source[7*32+:32]=observation_sequence;
    assign diag_source[8*32+:32]=observation_age;
    assign diag_source[9*32+:192]={16'b0,snapshot};
    assign diag_source[15*32+:32]=online_reason;
endmodule
