// Independent geometry observer, not a video/pixel capture interface.
// DE/HS/VS each pass two flops in RX. Counts are diagnostic observations;
// they do not certify the external source-synchronous RGB timing interface.
// Snapshot is serialized through ACK + DATA single-bit synchronizers. No
// unsynchronized multi-bit bus crosses domains, even while clocks stop.
// snapshot={frame_id32,frame_pixels32,wmin16,wmax16,height16,
//           htotal_min16,htotal_max16,vtotal16,flags16} (176 bits).
module hdmi_rx_geometry #(
 parameter integer CW=16, FW=32, TIMEOUT_CYCLES=100000000
)(input wire sys_clk,pix_clk,rst_n,de,hs,vs,request,
 output reg busy,valid,timed_out,output reg [175:0] snapshot);
 localparam [CW-1:0] CMAX={CW{1'b1}};
 localparam [FW-1:0] FMAX={FW{1'b1}};
 (* syn_preserve=1,async_reg="true" *) reg [1:0] release_rx=0;
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)release_rx<=0;else release_rx<={release_rx[0],1'b1};
 (* syn_preserve=1,async_reg="true" *) reg [1:0] de_pipe=0,hs_pipe=0,vs_pipe=0;
 reg de_d=0,hs_d=0,vs_d=0;
 wire de_rise=de_pipe[1]&&!de_d,de_fall=!de_pipe[1]&&de_d;
 wire hs_rise=hs_pipe[1]&&!hs_d,vs_rise=vs_pipe[1]&&!vs_d;
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin de_pipe<=0;hs_pipe<=0;vs_pipe<=0;de_d<=0;hs_d<=0;vs_d<=0;end
  else if(release_rx[1])begin
   de_pipe<={de_pipe[0],de};hs_pipe<={hs_pipe[0],hs};vs_pipe<={vs_pipe[0],vs};
   de_d<=de_pipe[1];hs_d<=hs_pipe[1];vs_d<=vs_pipe[1];
  end
 end
 reg seen_frame=0,seen_hs=0,line_has_de=0;
 reg [1:0] frame_boundaries=0;
 reg [CW-1:0] width_count=0,wmin=CMAX,wmax=0,height=0;
 reg [CW-1:0] h_ticks=0,hmin=CMAX,hmax=0,hs_count=0;
 reg [FW-1:0] frame_pixels=0;reg [31:0] frame_id=0;
 reg [15:0] flags=0;
 reg [15:0] closing_flags;
 always @*begin
  closing_flags=flags;
  if(height==0)closing_flags[0]=1;
  if(height!=0 && wmin!=wmax)closing_flags[1]=1;
  if(hmax!=0 && hmin!=hmax)closing_flags[2]=1;
  if(de_pipe[1]||de_d)closing_flags[5]=1;
  if(hs_count==0 || hmax==0)closing_flags[6]=1;
 end
 wire [175:0] closing_snapshot={frame_id,{{(32-FW){1'b0}},frame_pixels},
  {{(16-CW){1'b0}},(height==0?{CW{1'b0}}:wmin)},
  {{(16-CW){1'b0}},wmax},{{(16-CW){1'b0}},height},
  {{(16-CW){1'b0}},(hmax==0?{CW{1'b0}}:hmin)},
  {{(16-CW){1'b0}},hmax},{{(16-CW){1'b0}},hs_count},closing_flags};
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin
   seen_frame<=0;seen_hs<=0;line_has_de<=0;width_count<=0;wmin<=CMAX;wmax<=0;
   height<=0;h_ticks<=0;hmin<=CMAX;hmax<=0;hs_count<=0;
   frame_pixels<=0;frame_id<=0;flags<=0;frame_boundaries<=0;
  end else if(release_rx[1])begin
   if(vs_rise)begin
    seen_frame<=1;seen_hs<=hs_rise;line_has_de<=0;width_count<=0;
    wmin<=CMAX;wmax<=0;height<=0;h_ticks<=hs_rise?1:0;hmin<=CMAX;hmax<=0;hs_count<=hs_rise?1:0;
    frame_pixels<=1;frame_id<=frame_id+1'b1;flags<=0;
    if(frame_boundaries!=2)frame_boundaries<=frame_boundaries+1'b1;
   end else if(seen_frame)begin
    if(frame_pixels==FMAX)flags[3]<=1;else frame_pixels<=frame_pixels+1'b1;
    if(h_ticks==CMAX)flags[3]<=1;else h_ticks<=h_ticks+1'b1;
    if(hs_rise)begin
     seen_hs<=1;h_ticks<=1;line_has_de<=0;
     if(hs_count==CMAX)flags[3]<=1;else hs_count<=hs_count+1'b1;
     if(seen_hs)begin
      if(h_ticks<hmin)hmin<=h_ticks;
      if(h_ticks>hmax)hmax<=h_ticks;
     end
    end
    if(de_rise)begin
     if(line_has_de&&!hs_rise)flags[4]<=1;
     line_has_de<=1;width_count<=1;
    end else if(de_pipe[1])begin
     if(width_count==CMAX)flags[3]<=1;else width_count<=width_count+1'b1;
    end
    if(de_fall)begin
     if(width_count<wmin)wmin<=width_count;
     if(width_count>wmax)wmax<=width_count;
     if(height==CMAX)flags[3]<=1;else height<=height+1'b1;
     width_count<=0;
    end
   end
  end
 end
 reg req_toggle=0,ack_toggle=0,serial_bit=0;
 (* syn_preserve=1,async_reg="true" *) reg [1:0] req_pipe=0;
 reg [175:0] payload=0;reg [7:0] remaining=0;
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin req_pipe<=0;payload<=0;remaining<=0;ack_toggle<=0;serial_bit<=0;end
  else if(release_rx[1])begin
   req_pipe<={req_pipe[0],req_toggle};
   if(req_pipe[1]!=ack_toggle)begin
    if(remaining!=0)begin
     serial_bit<=payload[175];payload<=payload<<1;
     remaining<=remaining-1'b1;ack_toggle<=req_pipe[1];
    end else if(vs_rise && frame_boundaries==2)begin
     serial_bit<=closing_snapshot[175];payload<=closing_snapshot<<1;
     remaining<=175;ack_toggle<=req_pipe[1];
    end
   end
  end
 end
 (* syn_preserve=1,async_reg="true" *) reg [1:0] ack_pipe=0,data_pipe=0;
 reg ack_seen=0;reg [1:0] settle=0;reg [7:0] bits_left=0;
 reg [175:0] assemble=0;reg [31:0] elapsed=0;
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin
   req_toggle<=0;ack_pipe<=0;data_pipe<=0;ack_seen<=0;settle<=0;bits_left<=0;
   assemble<=0;elapsed<=0;busy<=0;valid<=0;timed_out<=0;snapshot<=0;
  end else begin
   ack_pipe<={ack_pipe[0],ack_toggle};data_pipe<={data_pipe[0],serial_bit};valid<=0;
   if(request&&!busy)begin
    req_toggle<=!req_toggle;bits_left<=176;assemble<=0;
    elapsed<=0;busy<=1;timed_out<=0;
   end
   if(busy)begin
    if(elapsed<TIMEOUT_CYCLES)elapsed<=elapsed+1'b1;
    else timed_out<=1;
    if(settle!=0)begin
     settle<=settle-1'b1;
     if(settle==1)begin
      assemble<={assemble[174:0],data_pipe[1]};bits_left<=bits_left-1'b1;
      if(bits_left==1)begin snapshot<={assemble[174:0],data_pipe[1]};valid<=1;busy<=0;end
      else req_toggle<=!req_toggle;
     end
    end else if(ack_pipe[1]!=ack_seen)begin ack_seen<=ack_pipe[1];settle<=3;end
   end
  end
 end
endmodule
