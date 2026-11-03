// H04T private admission policy. Does not interpret the old 0x209c word.
// All inputs are SYS-domain committed observations, never raw pixel CDC buses.
module hdmi_observed_qualification #(
    parameter W=1920,H=1080,HTOTAL=2200,VTOTAL=1125,
    parameter OBS_TTL=10000000, GEO_START_TTL=5000000,
    parameter GEO_TTL=2500000, RESET_HOLD_CYCLES=8
)(
    input wire clk,rst_n,rx_ready,tx_error,
    input wire observation_valid,last_observation_error,observation_busy,
    input wire [31:0] observation_raw,observation_sequence,observation_age,
    input wire geo_valid,geo_timeout,
    input wire [175:0] geometry,
    input wire [31:0] geo_epoch,
    output wire online,
    (* syn_preserve=1 *) output reg geometry_reset_n=0,
    (* syn_preserve=1 *) output reg [31:0] epoch=0,
    output wire [31:0] reason,
    output reg [31:0] geometry_age=0
);
    // Unknown/reserved bits are deliberately not interpreted.
    wire observed_bits_good=(observation_raw&32'h00007f0f)==32'h00007f07;
    reg busy_d=0,attempt_open=0;
    reg [31:0] attempt_epoch=0,last_sequence=0;
    reg seen_sequence=0;
    wire new_observation=observation_valid&&
        (!seen_sequence||observation_sequence!=last_sequence);
    wire sequence_bad=new_observation&&seen_sequence&&
        observation_sequence!=(last_sequence+32'd1);
    wire attempt_bad=new_observation&&(observation_busy||!attempt_open||attempt_epoch!=epoch);
    wire observation_bad=!observation_valid||last_observation_error||
        observation_age>=OBS_TTL||!observed_bits_good||sequence_bad||attempt_bad;
    wire accepted_observation=new_observation&&!observation_bad;

    wire [31:0] frame=geometry[175:144];
    wire shape_good=geometry[15:0]==0 && geometry[143:112]==HTOTAL*VTOTAL &&
        geometry[111:96]==W && geometry[95:80]==W && geometry[79:64]==H &&
        geometry[63:48]==HTOTAL && geometry[47:32]==HTOTAL && geometry[31:16]==VTOTAL;
    reg [1:0] observation_count=0,geometry_count=0;
    reg [31:0] last_frame=0;
    wire geometry_shape_bad=geometry_reset_n&&geo_valid&&!shape_good;
    wire geometry_epoch_bad=geometry_reset_n&&geo_valid&&(geo_epoch!=epoch);
    // An initial zero frame is not a complete epoch. Subsequent natural wrap
    // is accepted only as the strict modulo-32-bit successor of ffffffff.
    wire geometry_frame_bad=geometry_reset_n&&geo_valid&&
        ((geometry_count==0&&frame==0)||
         (geometry_count!=0&&frame!=(last_frame+32'd1)));
    wire geometry_expired=geometry_reset_n&&
        (geometry_count==0 ? geometry_age>=GEO_START_TTL : geometry_age>=GEO_TTL);
    wire geometry_timed_out=geometry_reset_n&&geo_timeout;
    wire reject_now=!rx_ready||tx_error||observation_bad||geometry_timed_out||
        geometry_shape_bad||geometry_epoch_bad||geometry_frame_bad||geometry_expired;
    (* syn_preserve=1 *) reg qualified=0;
    reg reject_latched=1;
    reg [31:0] reset_hold=RESET_HOLD_CYCLES;
    // Only registered state drives the asynchronous capture/FIFO reset.
    // A newly committed bad input wins at the next SYS decision edge (<=1
    // SYS period); mutable sequence/frame/age comparators must not glitch it.
    assign online=rst_n&&qualified&&geometry_reset_n;
    // Low bits are individual current blockers. High bits describe the FSM.
    assign reason={12'b0,online,geometry_count==2,geometry_reset_n,observation_count==2,
        2'b0,geometry_expired,geometry_frame_bad,geometry_epoch_bad,geometry_shape_bad,
        geometry_timed_out,attempt_bad,sequence_bad,!observed_bits_good,
        observation_age>=OBS_TTL,last_observation_error,!observation_valid,
        tx_error,!rx_ready,!rst_n};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy_d<=0;attempt_open<=0;attempt_epoch<=0;
            seen_sequence<=0;last_sequence<=0;
            observation_count<=0;geometry_count<=0;last_frame<=0;
            geometry_reset_n<=0;geometry_age<=0;epoch<=0;
            qualified<=0;reject_latched<=1;reset_hold<=RESET_HOLD_CYCLES;
        end else begin
            // These histories survive qualification losses. Clearing busy_d
            // would falsely relabel an old, still-busy transaction as new.
            busy_d<=observation_busy;
            if(observation_busy&&!busy_d)begin
                attempt_epoch<=epoch;attempt_open<=1;
            end
            if((busy_d&&!observation_busy)||new_observation)attempt_open<=0;
            if(new_observation)begin
                seen_sequence<=1;last_sequence<=observation_sequence;
            end
            if(reject_now)begin
                // One epoch transition per continuous rejection episode.
                // In-flight transactions keep their original attempt_epoch.
                if(!reject_latched)epoch<=epoch+1'b1;
                reject_latched<=1;
                qualified<=0;geometry_reset_n<=0;
                observation_count<=0;geometry_count<=0;last_frame<=0;
                geometry_age<=0;reset_hold<=RESET_HOLD_CYCLES;
            end else begin
                reject_latched<=0;
                if(accepted_observation&&observation_count<2)
                    observation_count<=observation_count+1'b1;
                if(!geometry_reset_n)begin
                    qualified<=0;geometry_age<=0;
                    if(reset_hold!=0)reset_hold<=reset_hold-1'b1;
                    else if(observation_count==2 ||
                            (accepted_observation&&observation_count==1))
                        geometry_reset_n<=1;
                end else begin
                    if(geometry_age!=32'hffffffff)geometry_age<=geometry_age+1'b1;
                    if(geo_valid)begin
                        // reject_now already checked epoch, complete shape,
                        // frame progress and BOTH watchdogs, with loss priority.
                        last_frame<=frame;geometry_age<=0;
                        if(geometry_count<2)geometry_count<=geometry_count+1'b1;
                        if(geometry_count>=1)qualified<=1;
                    end
                end
            end
        end
    end
endmodule
