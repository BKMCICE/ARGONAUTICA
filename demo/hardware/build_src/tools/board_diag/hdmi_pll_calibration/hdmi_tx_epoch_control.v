// Receiver-first startup; physical reset is shared POR only.
// Post-init probes use documented MS7210 frequency/DVIN detector registers.
module hdmi_tx_epoch_control #(
 parameter integer GAP_CYCLES=50000,DETECT_WAIT_CYCLES=5000000
)( input wire clk,rst_n,rx_ready,allow_next_sweep,
 output wire hdmi_rst_n,scl,inout wire sda,
 output wire init_done,init_error,output wire safe_restart,output reg [7:0] phase_readback,hpd_readback,
 output reg [7:0] clock_before,clock_after,clock_asserted,
 output reg [7:0] freq_readback,output reg [23:0] dvin_htotal,dvin_vtotal,dvin_width);
 wire init_scl,unused_init_reset,core_error;
 assign hdmi_rst_n=rst_n;
 ms7210_init init(.clk(clk),.rst_n(rst_n&&rx_ready),
 .hdmi_rst_n(unused_init_reset),.scl(init_scl),.sda(sda),
 .init_done(init_done),.init_error(core_error));
 reg clock_validation_error;
 reg sweep_complete;
 (* async_reg="true",syn_preserve=1 *) reg [1:0] sda_idle;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)sda_idle<=0;else sda_idle<={sda_idle[0],sda};
 reg start=0,issued=0,probe_error=0;reg [4:0] index;
 reg [31:0] delay_count=GAP_CYCLES;
 wire probe_scl,busy,done,error;wire [7:0] value;
 reg rd;reg [15:0] address;reg [7:0] data;
 assign init_error=core_error|probe_error;
 // The preceding command has completed STOP and the next start is still
 // separated by the original nonzero gap. Both masters are released.
 assign safe_restart=init_done&&!init_error&&sweep_complete&&(index==0)&&
  !issued&&!busy&&(delay_count>2)&&init_scl&&probe_scl&&sda_idle[1];
 assign scl=init_done?probe_scl:init_scl;
 hdmi_loop_i2c master(.clk(clk),.rst_n(rst_n&&init_done),.start(start),.rd(rd),
 .address(address),.write_data(data),.busy(busy),.done(done),.error(error),
 .read_data(value),.scl(probe_scl),.sda(sda));
 always @*begin
  rd=1;address=16'h1281;data=0;
  case(index)
   0:address=16'h1281;
   1:address=16'h0502;
   2:begin rd=0;address=16'h0019;data=8'h07;end
   3:address=16'h001e;
   4:begin rd=0;address=16'h1207;data=8'h03;end
   5:begin rd=0;address=16'h1207;data=8'h01;end
   6:address=16'h1208;
   7:address=16'h1209;
   8:address=16'h120a;
   9:begin rd=0;address=16'h1207;data=8'h13;end
   10:begin rd=0;address=16'h1207;data=8'h11;end
   11:address=16'h1208;
   12:address=16'h1209;
   13:address=16'h120a;
   14:begin rd=0;address=16'h1207;data=8'h23;end
   15:begin rd=0;address=16'h1207;data=8'h21;end
   16:address=16'h1208;
   17:address=16'h1209;
   18:address=16'h120a;
   19:address=16'h000a;
   20:begin rd=0;address=16'h000a;data=clock_before&8'hef;end
   21:address=16'h000a;
   22:begin rd=0;address=16'h000a;data=clock_before|8'h10;end
   23:address=16'h000a;
   24:address=16'h0008;
   default:address=16'h1281;
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   start<=0;issued<=0;probe_error<=0;index<=0;sweep_complete<=0;delay_count<=GAP_CYCLES;
   clock_before<=0;clock_after<=0;clock_asserted<=0;clock_validation_error<=0;phase_readback<=0;hpd_readback<=0;freq_readback<=0;dvin_htotal<=0;dvin_vtotal<=0;dvin_width<=0;
  end
  else begin
   start<=0;
   if(init_done&&!probe_error&&!(sweep_complete&&index==0&&!allow_next_sweep))begin
    if(delay_count!=0)delay_count<=delay_count-1'b1;
    else if(!issued&&!busy&&sda_idle[1])begin start<=1;issued<=1;end
    if(issued&&done)begin
     issued<=0;delay_count<=(index==5||index==10||index==15||index==20)?DETECT_WAIT_CYCLES:GAP_CYCLES;
     if(error)probe_error<=1;
     else begin
      case(index)
       0:phase_readback<=value;
       1:hpd_readback<=value;
       3:freq_readback<=value;
       6:dvin_htotal[7:0]<=value;
       7:dvin_htotal[15:8]<=value;
       8:dvin_htotal[23:16]<=value;
       11:dvin_vtotal[7:0]<=value;
       12:dvin_vtotal[15:8]<=value;
       13:dvin_vtotal[23:16]<=value;
       16:dvin_width[7:0]<=value;
       17:dvin_width[15:8]<=value;
       18:dvin_width[23:16]<=value;
       19:clock_before<=value;
       21:begin clock_asserted<=value;if(value!=(clock_before&8'hef))clock_validation_error<=1;end
       23:begin clock_after<=value;if(value!=(clock_before|8'h10)||clock_validation_error)probe_error<=1;end
       24:if(!value[4])probe_error<=1;
       default:begin end
      endcase
      if(index==(allow_next_sweep?18:24))sweep_complete<=1;
      index<=(index==(allow_next_sweep?18:24))?0:index+1'b1;
     end
    end
   end
  end
 end
endmodule
