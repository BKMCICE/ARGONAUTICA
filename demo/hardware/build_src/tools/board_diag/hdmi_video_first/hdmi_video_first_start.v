// H02D startup-only experiment, SYS domain. Snapshot already crosses the
// existing serialized CDC. Never use the raw RX multi-bit bus in this block.
// Two matching fresh complete snapshots enable video; two more release TX.
// TX release is latched until global reset: no new hotplug policy is tested.
module hdmi_video_first_start(input wire clk,rst_n,rx_ready,
 input wire valid,timed_out,input wire [175:0] snapshot,
 output reg video_enable,tx_release,output reg [2:0] stable_count);
 reg [127:0] previous_mode;
 reg [31:0] previous_frame;
 wire [31:0] frame=snapshot[175:144];
 wire [127:0] mode=snapshot[143:16];
 wire well_formed=(snapshot[15:0]==0) && (snapshot[143:112]!=0) &&
  (snapshot[111:96]!=0) && (snapshot[111:96]==snapshot[95:80]) &&
  (snapshot[79:64]!=0) && (snapshot[63:48]==snapshot[47:32]) &&
  (snapshot[63:48]>snapshot[95:80]) && (snapshot[31:16]>snapshot[79:64]);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   video_enable<=0;tx_release<=0;stable_count<=0;previous_mode<=0;previous_frame<=0;
  end else if(!tx_release)begin
   if(!rx_ready || timed_out || (valid&&!well_formed))begin
    video_enable<=0;stable_count<=0;previous_mode<=0;previous_frame<=0;
   end else if(valid && frame!=previous_frame)begin
    previous_mode<=mode;previous_frame<=frame;
    if(stable_count==0 || mode!=previous_mode || frame<previous_frame)begin
     stable_count<=1;video_enable<=0;
    end else begin
     stable_count<=stable_count+1'b1;
     if(stable_count>=1)video_enable<=1;
     if(stable_count==3)tx_release<=1;
    end
   end
  end
 end
endmodule
