// H02F experiment: exactly one replay of the original TX initialization.
// Child reset is SOFTWARE state only; shared physical R17 stays global POR.
module hdmi_tx_reinit_control #(
 parameter integer SOFT_RESET_CYCLES=50000
)(input wire clk,rst_n,rx_ready,
 output wire hdmi_rst_n,scl,inout wire sda,
 output wire init_done,init_error,output wire [7:0] phase_readback,hpd_readback,
 output wire [7:0] freq_readback,output wire [23:0] dvin_htotal,dvin_vtotal,dvin_width,
 output reg [1:0] init_pass_count,output reg replay_started,
 output wire software_reset_active,output reg [7:0] clock_before,clock_after,clock_asserted);
 wire [7:0] epoch_before,epoch_after,epoch_asserted;
 wire safe_restart,core_done,core_error,unused_reset;
 reg soft_run,previous_done;
 reg [31:0] reset_count;
 assign hdmi_rst_n=rst_n;
 assign init_done=core_done;
 assign init_error=core_error;
 assign software_reset_active=!soft_run;
 hdmi_tx_epoch_control epoch(.clk(clk),.rst_n(rst_n&&soft_run),.rx_ready(rx_ready),.allow_next_sweep(replay_started),
 .hdmi_rst_n(unused_reset),.scl(scl),.sda(sda),.init_done(core_done),.init_error(core_error),
 .phase_readback(phase_readback),.hpd_readback(hpd_readback),.freq_readback(freq_readback),
 .dvin_htotal(dvin_htotal),.dvin_vtotal(dvin_vtotal),.dvin_width(dvin_width),
 .safe_restart(safe_restart),.clock_before(epoch_before),.clock_after(epoch_after),.clock_asserted(epoch_asserted));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   clock_before<=0;clock_after<=0;clock_asserted<=0;soft_run<=1;reset_count<=0;previous_done<=0;init_pass_count<=0;replay_started<=0;
  end else begin
   previous_done<=core_done;
   if(core_done&&!previous_done&&init_pass_count!=2) init_pass_count<=init_pass_count+1'b1;
   if(!soft_run)begin
    if(reset_count==SOFT_RESET_CYCLES-1)begin soft_run<=1;reset_count<=0;end
    else reset_count<=reset_count+1'b1;
   end else if(!replay_started && init_pass_count==1 && safe_restart && !core_error)begin
    clock_before<=epoch_before;clock_after<=epoch_after;clock_asserted<=epoch_asserted;soft_run<=0;reset_count<=0;replay_started<=1;
   end
  end
 end
endmodule
