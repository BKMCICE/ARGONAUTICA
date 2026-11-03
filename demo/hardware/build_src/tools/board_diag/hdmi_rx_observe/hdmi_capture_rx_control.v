// H12 private S clone: verify EDID before its first DDC-visible release.
// MS7200 000A[2] is EDID software reset, NOT an HPD control bit.
// Keep all 300 original INIT writes and their order; insert the 256 reads
// between entries293 and294 while 000C[7]=1 and 000A[2]=0.
// 209C/SETTING/1281/read2180 observation and external interfaces unchanged.
// The 300 INIT transactions and seven frequency-change settings are separate.
// See reference_trace.json: do not flatten all 311 reference ROM entries.
module hdmi_capture_rx_control #(
 parameter integer Q=125, BOOT_WAIT=5000000, GAP=50000, POLL_WAIT=1000000
)(input wire clk,rst_n, output wire scl,inout wire sda,
 output reg initialized,edid_ok,setting_done,
 output reg [3:0] fault,output reg [15:0] fault_address,
 output reg [7:0] fault_actual,fault_expected,
 output reg [31:0] frequency_status,output reg [7:0] phase_before,phase_after,
 output reg frequency_update,output reg [31:0] frequency_sample,poll_sequence,
 output wire [15:0] debug_progress,
 output reg observation_valid,last_observation_error,output wire observation_busy,
 output reg [31:0] observation_raw,observation_sequence,observation_age);
 `include "../hdmi_rx_table.vh"
 reg [7:0] phase_target;
 reg [3:0] phase;
 reg [8:0] index;
 assign debug_progress={3'b0,phase,index};
 assign observation_busy=(phase==4'd12);
 // Four-byte read: START1 + 4 TX bytes*36 + restart3 + 4 RX*35 + STOP3 =291Q.
 // Include both legacy GAPs and eight SYS clocks of handshake margin.
 localparam [63:0] OBSERVATION_SLOT_CYCLES=64'd2*GAP+64'd291*Q+64'd8;
 localparam OBSERVATION_SLOT_OK=(Q>0)&&(GAP>=0)&&(POLL_WAIT>=0)&&
                              (POLL_WAIT>=OBSERVATION_SLOT_CYCLES);
 reg [31:0] observation_gap;
 reg [31:0] delay_count;
 reg issued,start;
 reg [15:0] address;
 reg [7:0] data;
 reg rd;
 wire busy,done,error;
 wire [7:0] result;wire [31:0] observation_result;
 reg [1:0] previous_frequency;
 hdmi_rx_i2c #(.Q(Q)) bus(.clk(clk),.rst_n(rst_n),.start(start),.rd(rd),
  .address(address),.write_data(data),.busy(busy),.done(done),.error(error),
  .read_data(result),.observation_data(observation_result),.scl(scl),.sda(sda));
 reg [23:0] cmd,expected;
 always @* begin
  cmd=rx_command(index);expected=rx_command(9'd38+index);
  address=16'h0003;data=8'h5a;rd=0;
  case(phase)
   1: rd=1;
   2: begin address=cmd[23:8];data=cmd[7:0];end
   3: begin address=16'h0d00+{7'b0,index};rd=1;end
   4: begin address=16'h000a;rd=1;end
   5: begin address=16'h209c+{7'b0,index};rd=1;end
   6: begin
    case(index)
     0:begin address=16'h1010;data=8'h01;end
     1:begin address=16'h1024;data=8'h00;end
     2:begin address=16'h0200;data=8'h00;end
     3:begin address=16'h1024;data=8'h70;end
     4:begin address=16'h0200;data=8'h07;end
     5:begin address=16'h0215;data=8'h01;end
     default:begin address=16'h0215;data=8'h00;end
    endcase
   end
   9:begin address=16'h1281;rd=1;end
   10:begin address=16'h1281;data=phase_target;end
   11:begin address=16'h1281;rd=1;end
   12:begin address=16'h2180;rd=1;end
   default:begin end
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   phase<=0;index<=0;delay_count<=BOOT_WAIT;issued<=0;start<=0;
   initialized<=0;edid_ok<=0;setting_done<=0;fault<=0;fault_address<=0;
   frequency_status<=0;previous_frequency<=0;phase_before<=0;phase_after<=0;phase_target<=0;
   fault_actual<=0;fault_expected<=0;frequency_update<=0;frequency_sample<=0;poll_sequence<=0;
   observation_valid<=0;last_observation_error<=0;observation_raw<=0;
   observation_sequence<=0;observation_age<=32'hffffffff;observation_gap<=0;
  end else begin
   start<=0;frequency_update<=0;
   // Access age, not freshness of the receiver's internal detector.
   if(observation_age!=32'hffffffff)observation_age<=observation_age+1'b1;
   if(fault==0&&phase!=12)begin
    if(delay_count!=0)delay_count<=delay_count-1'b1;
    else if(!issued && !busy)begin start<=1;issued<=1;end
    if(issued && done)begin
     issued<=0;delay_count<=GAP;
     if(error)begin fault<=1;fault_address<=address;end
     else case(phase)
      0:phase<=1;
      1:begin
       if(result!=8'h5a)begin fault<=2;fault_address<=address;fault_actual<=result;fault_expected<=8'h5a;end
       else begin phase<=2;index<=0;end
      end
      2:begin
       // Entry293 is the final EDID byte. Verify before entry294 returns
       // RAM ownership to DDC and entry295 releases EDID software reset.
       if(index==293)begin index<=0;phase<=3;end
       else if(index==299)begin initialized<=1;index<=0;phase<=4;end
       else index<=index+1'b1;
      end
      3:begin
       if(result!=expected[7:0])begin fault<=3;fault_address<=address;fault_actual<=result;fault_expected<=expected[7:0];end
       else if(index==255)begin edid_ok<=1;phase<=2;index<=294;end
       else index<=index+1'b1;
      end
      4:begin
       if(result!=8'h04)begin fault<=4;fault_address<=address;fault_actual<=result;fault_expected<=8'h04;end
       else begin phase<=5;index<=0;end
      end
      5:begin
       case(index)
        0:frequency_status[7:0]<=result;
        1:frequency_status[15:8]<=result;
        2:frequency_status[23:16]<=result;
        3:frequency_status[31:24]<=result;
        default:begin end
       endcase
       if(index==3)begin
        frequency_sample<={result,frequency_status[23:0]};frequency_update<=1;poll_sequence<=poll_sequence+1'b1;
        index<=0;delay_count<=POLL_WAIT;
        previous_frequency<=frequency_status[17:16];
        // EDID diagnostic reads can outlast the initial status00 interval.
        // Configure on the first valid10 sample too, even if first seen01.
        // Subsequent hotplug recovery retains the reference00->10 trigger.
        if(frequency_status[17:16]==2 && (!setting_done || previous_frequency==0))phase<=6;
        else if(OBSERVATION_SLOT_OK)begin phase<=12;observation_gap<=GAP;end
       end else index<=index+1'b1;
      end
      6:begin
       if(index==6)begin setting_done<=0;index<=0;phase<=9;end
       else index<=index+1'b1;
      end
      9:begin phase_before<=result;phase_target<=result|8'h04;phase<=10;end
      10:phase<=11;
      11:begin
       phase_after<=result;
       if(result!=phase_target)begin fault<=6;fault_address<=16'h1281;fault_actual<=result;fault_expected<=phase_target;end
       else begin setting_done<=1;index<=0;phase<=5;end
      end
      default:begin fault<=5;fault_address<=address;end
     endcase
    end
   end
   if(fault==0&&phase==12)begin
    // This is the original poll deadline, never restarted by observation.
    if(delay_count!=0)delay_count<=delay_count-1'b1;
    if(observation_gap!=0)observation_gap<=observation_gap-1'b1;
    else if(!issued&&!busy)begin start<=1;issued<=1;end
    if(issued&&done)begin
     issued<=0;phase<=5;observation_gap<=0;
     // An observation error belongs here, never in the legacy RX fault path.
     last_observation_error<=error;
     if(!error)begin
      observation_raw<=observation_result;observation_sequence<=observation_sequence+1'b1;
      observation_valid<=1;observation_age<=0;
     end
    end
   end
  end
 end
endmodule
