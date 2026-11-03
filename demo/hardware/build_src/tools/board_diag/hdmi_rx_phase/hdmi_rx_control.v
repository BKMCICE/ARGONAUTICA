// H01 only: ACK-checked initialization, complete EDID readback, live status.
// The 300 INIT transactions and seven frequency-change settings are separate.
// See reference_trace.json: do not flatten all 311 reference ROM entries.
module hdmi_rx_control #(
 parameter integer Q=125, BOOT_WAIT=5000000, GAP=50000, POLL_WAIT=1000000
)(input wire clk,rst_n, output wire scl,inout wire sda,
 output reg initialized,edid_ok,setting_done,
 output reg [3:0] fault,output reg [15:0] fault_address,
 output reg [7:0] fault_actual,fault_expected,
 output reg [31:0] frequency_status,output reg [7:0] phase_before,phase_after);
 `include "../hdmi_rx_table.vh"
 reg [7:0] phase_target;
 reg [3:0] phase;
 reg [8:0] index;
 reg [31:0] delay_count;
 reg issued,start;
 reg [15:0] address;
 reg [7:0] data;
 reg rd;
 wire busy,done,error;
 wire [7:0] result;
 reg [1:0] previous_frequency;
 hdmi_rx_i2c #(.Q(Q)) bus(.clk(clk),.rst_n(rst_n),.start(start),.rd(rd),
  .address(address),.write_data(data),.busy(busy),.done(done),.error(error),
  .read_data(result),.scl(scl),.sda(sda));
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
   // MS7200 register map 0x000c bit7: host EDID RAM access vs DDC.
   // Reference INIT returns bit7 to zero at entry294. Enable for readback
   // and return ownership to DDC before polling or source enumeration.
   7:begin address=16'h000c;data=8'h80;end
   8:begin address=16'h000c;data=8'h00;end
   9:begin address=16'h1281;rd=1;end
   10:begin address=16'h1281;data=phase_target;end
   11:begin address=16'h1281;rd=1;end
   default:begin end
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   phase<=0;index<=0;delay_count<=BOOT_WAIT;issued<=0;start<=0;
   initialized<=0;edid_ok<=0;setting_done<=0;fault<=0;fault_address<=0;
   frequency_status<=0;previous_frequency<=0;phase_before<=0;phase_after<=0;phase_target<=0;
   fault_actual<=0;fault_expected<=0;
  end else begin
   start<=0;
   if(fault==0)begin
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
       if(index==299)begin initialized<=1;index<=0;phase<=7;end
       else index<=index+1'b1;
      end
      3:begin
       if(result!=expected[7:0])begin fault<=3;fault_address<=address;fault_actual<=result;fault_expected<=expected[7:0];end
       else if(index==255)begin edid_ok<=1;phase<=8;index<=0;end
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
        index<=0;delay_count<=POLL_WAIT;
        previous_frequency<=frequency_status[17:16];
        // EDID diagnostic reads can outlast the initial status00 interval.
        // Configure on the first valid10 sample too, even if first seen01.
        // Subsequent hotplug recovery retains the reference00->10 trigger.
        if(frequency_status[17:16]==2 && (!setting_done || previous_frequency==0))phase<=6;
       end else index<=index+1'b1;
      end
      6:begin
       if(index==6)begin setting_done<=0;index<=0;phase<=9;end
       else index<=index+1'b1;
      end
      7:begin phase<=3;index<=0;end
      8:begin phase<=4;index<=0;end
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
  end
 end
endmodule
