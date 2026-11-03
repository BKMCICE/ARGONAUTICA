`timescale 1ns/1ps
module tb_observed_frontend;
 reg sys_clk=0,ui_clk=0,rx_clk=0,run_pixel=1;
 always #10 sys_clk=~sys_clk;always #5 ui_clk=~ui_clk;
 always #3.367 if(run_pixel)rx_clk=~rx_clk;
 reg de=0,hs=0,vs=0;reg [23:0] rgb=0;reg bad_shape=0;
 tri1 rx_sda,tx_sda;wire dr,ready,capreset,prst,pclk,ode,ohs,ovs;wire [7:0] r,g,b;wire [26:0] sample;wire [511:0] diag;
 hdmi_capture_frontend #(.GEO_INTERVAL_CYCLES(32),.EXPECT_W(16),.EXPECT_H(8),.EXPECT_HTOTAL(128),.EXPECT_VTOTAL(64),
  .QUAL_OBS_TTL(2000),.QUAL_GEO_START_TTL(20000),.QUAL_GEO_TTL(10000)) dut(
  .sys_clk(sys_clk),.hdmi_rx_pixclk(rx_clk),.hdmi_rx_de(de),.hdmi_rx_hs(hs),.hdmi_rx_vs(vs),.status_code(8'h55),.sys_pll_ready(1'b1),
  .hdmi_rx_r(rgb[23:16]),.hdmi_rx_g(rgb[15:8]),.hdmi_rx_b(rgb[7:0]),.hdmi_rx_iic_scl(),.hdmi_rx_iic_sda(rx_sda),
  .hdmi_rst_n(prst),.hdmi_scl(),.hdmi_sda(tx_sda),.hdmi_pclk(pclk),.hdmi_vs(ovs),.hdmi_hs(ohs),.hdmi_de(ode),
  .hdmi_r(r),.hdmi_g(g),.hdmi_b(b),.capture_sample(sample),.capture_ready(ready),.capture_reset_n(capreset),.diag_reset_n(dr),.diag_source(diag));
 defparam dut.por.COUNTER_BITS=4,dut.geometry.TIMEOUT_CYCLES=20000;
 defparam dut.u_hdmi_init.QUARTER_CYCLES=2,dut.u_hdmi_init.RESET_CYCLES=4,dut.u_hdmi_init.WRITE_GAP_CYCLES=2,dut.u_hdmi_init.SETTLE_CYCLES=6;
 wire [31:0] starts,stops,bytes;
 q_tx_wire_slave tx(.scl(dut.hdmi_scl),.sda(tx_sda),.reset_n(dut.tx_software_reset_n),.ack_enable(1'b1),.starts(starts),.stops(stops),.bytes(bytes));
 reg obs_enable=1,obs_good=1,obs_error=0;wire ov,ob,oe;wire [31:0] ow,os,oa;
 t_observation_stimulus observer(.clk(sys_clk),.rst_n(dr),.enable(obs_enable),.good(obs_good),.error(obs_error),.valid(ov),.busy(ob),.last_error(oe),.raw(ow),.seq(os),.age(oa));
 initial begin
  force dut.rx_init=1;force dut.edid_ok=1;force dut.setting_done=1;force dut.fault=0;
  force dut.frequency_sample=32'h00035800;force dut.frequency_update=1;
  force dut.observation_valid=ov;force dut.observation_busy=ob;force dut.last_observation_error=oe;
  force dut.observation_raw=ow;force dut.observation_sequence=os;force dut.observation_age=oa;
 end
 integer x=0,y=0,xx,yy;
 always @(posedge rx_clk)begin #0.1;hs=x<4;vs=y<2;de=x>=12&&x<(bad_shape?29:28)&&y>=5&&y<13;xx=x-12;yy=y-5;
  rgb={8'(xx*7+yy*3+23),8'(xx*11+yy*5+106),8'(xx*13+yy*17+190)};
  if(x==127)begin x=0;if(y==63)y=0;else y=y+1;end else x=x+1;
 end
 reg snap_reset=0,request=0;wire busy,valid,timeout;wire [31:0] snap_seq;wire [511:0] data;
 reg [511:0] expected=0;integer freeze_count=0;
 hdmi_frontend_snapshot #(.TIMEOUT_CYCLES(20000)) snap(.sys_clk(sys_clk),.ui_clk(ui_clk),.reset_n(snap_reset),.source_data(diag),.request(request),.busy(busy),.valid(valid),.timed_out(timeout),.snapshot_sequence(snap_seq),.data(data));
 always @(posedge sys_clk)if(snap.srst_n&&snap.req_pipe[1]!=snap.ack_toggle&&snap.remaining==0)begin expected=diag;freeze_count=freeze_count+1;end
 task take;integer guard;reg [31:0] before_seq;begin
  before_seq=snap_seq;@(negedge ui_clk);request=1;@(negedge ui_clk);request=0;guard=0;
  while(snap_seq==before_seq&&guard<20000)begin @(negedge ui_clk);guard=guard+1;end
  if(guard==20000||data!==expected||timeout||!valid||data[31:0]!=32'h48303454)$fatal(1,"T full512 snapshot");
 end endtask
 task wait_online;integer guard;begin guard=0;while(!ready&&guard<60000)begin @(negedge sys_clk);guard=guard+1;end
  if(!ready)$fatal(1,"T real frontend failed to qualify reason=%h epoch=%h geo=%h",dut.online_reason,dut.qualification_epoch,dut.snapshot);
  if(dut.live_input.geometry_count!=2||!capreset||!dut.geometry_run_n)$fatal(1,"T missing two real frames");
 end endtask
 task wait_offline;integer guard;begin guard=0;while(ready&&guard<22000)begin @(negedge sys_clk);guard=guard+1;end
  if(ready||capreset)$fatal(1,"T qualification did not revoke");
 end endtask
 reg [31:0] old_epoch;integer checks=0;reg seen_reset=0;
 always @(posedge prst)seen_reset=1;
 always @(negedge prst)if(seen_reset)$fatal(1,"Input qualification reset physical chip");
 always @(negedge sys_clk)if(dr)begin
  if(ready!==capreset)$fatal(1,"capture reset mismatch");
  if(diag[0+:32]!=32'h48303454||diag[96+:32]!=dut.qualification_epoch||diag[480+:32]!=dut.online_reason)$fatal(1,"T ABI epoch/reason");
  if(dut.tx_done&&dut.tx_error)$fatal(1,"TX error");checks=checks+1;
 end
 initial begin
  wait(dr);snap_reset=1;wait_online;take;
  if(starts!=49||stops!=49||bytes!=196)$fatal(1,"TX49 real wire");
  $display("T_DOCUMENTED_ACTIVITY_WITH_OLD_STATE3_AND_REAL_GEOMETRY_PASS");
  old_epoch=dut.qualification_epoch;obs_good=0;wait_offline;repeat(10)@(negedge sys_clk);
  if(dut.qualification_epoch==old_epoch||dut.geometry_run_n)$fatal(1,"bad activity failed epoch reset");
  if(!dut.status_video_ready||!dut.hdmi_rst_n||stops!=49)$fatal(1,"input loss touched independent OUT");
  obs_good=1;wait_online;take;
  $display("T_ACTIVITY_REJECT_NEW_EPOCH_TWO_GEOMETRIES_PASS");
  old_epoch=dut.qualification_epoch;run_pixel=0;wait_offline;repeat(10)@(negedge sys_clk);
  if(dut.qualification_epoch==old_epoch||dut.geometry_run_n)$fatal(1,"pixel-stop no epoch reset");
  run_pixel=1;wait_online;take;
  $display("T_STOPPED_PIXEL_CLOCK_OLD_HANDSHAKE_DISCARDED_RECOVERY_PASS");
  obs_enable=0;wait_offline;obs_enable=1;wait_online;
  $display("T_STICKY_VALID_CANNOT_REFRESH_OBSERVATION_PASS");
  bad_shape=1;wait_offline;repeat(5000)@(negedge sys_clk);if(ready)$fatal(1,"bad shape admitted");
  bad_shape=0;wait_online;take;
  $display("T_WRONG_REAL_RASTER_REJECT_AND_RECOVER_PASS");
  if(freeze_count!=4||checks<10000||stops!=49)$fatal(1,"T coverage counters");
  $display("H04T_FRONTEND_EPOCH_GEOMETRY_PASS checks=%0d snapshots=%0d",checks,freeze_count);$finish;
 end
 initial begin #20000000;$fatal(1,"T frontend timeout");end
endmodule
