// H04I serialized SYS->UI snapshot. Payload is frozen at source on first bit.
// Only request, acknowledgment and data BIT cross through two-flop chains.
// UI publishes the entire snapshot atomically and increments a sequence.
// A timeout never abandons a pending toggle: stopped clocks may later resume.
module hdmi_frontend_snapshot #(
    parameter WIDTH=512,TIMEOUT_CYCLES=1000000
)(input wire sys_clk,ui_clk,reset_n,
  input wire [WIDTH-1:0] source_data,input wire request,
  output reg busy=0,valid=0,timed_out=0,
  output reg [31:0] snapshot_sequence=0,output reg [WIDTH-1:0] data=0);
    (* async_reg="true",syn_preserve=1 *)reg [1:0] sys_reset=0,ui_reset=0;
    always @(posedge sys_clk or negedge reset_n)
        if(!reset_n)sys_reset<=0;else sys_reset<={sys_reset[0],1'b1};
    always @(posedge ui_clk or negedge reset_n)
        if(!reset_n)ui_reset<=0;else ui_reset<={ui_reset[0],1'b1};
    wire srst_n=sys_reset[1],urst_n=ui_reset[1];
    reg req_toggle=0,ack_toggle=0,serial_bit=0;
    (* async_reg="true",syn_preserve=1 *)reg [1:0] req_pipe=0,ack_pipe=0,data_pipe=0;
    reg [WIDTH-1:0] payload=0,assemble=0;
    reg [$clog2(WIDTH+1)-1:0] remaining=0,bits_left=0;
    reg ack_seen=0;reg [1:0] settle=0;reg [31:0] elapsed=0;
    always @(posedge sys_clk or negedge srst_n)begin
        if(!srst_n)begin req_pipe<=0;payload<=0;remaining<=0;ack_toggle<=0;serial_bit<=0;end
        else begin
            req_pipe<={req_pipe[0],req_toggle};
            if(req_pipe[1]!=ack_toggle)begin
                if(remaining==0)begin
                    serial_bit<=source_data[WIDTH-1];payload<=source_data<<1;remaining<=WIDTH-1;
                end else begin
                    serial_bit<=payload[WIDTH-1];payload<=payload<<1;remaining<=remaining-1'b1;
                end
                ack_toggle<=req_pipe[1];
            end
        end
    end
    always @(posedge ui_clk or negedge urst_n)begin
        if(!urst_n)begin
            req_toggle<=0;ack_pipe<=0;data_pipe<=0;ack_seen<=0;settle<=0;
            bits_left<=0;assemble<=0;elapsed<=0;busy<=0;valid<=0;timed_out<=0;snapshot_sequence<=0;data<=0;
        end else begin
            ack_pipe<={ack_pipe[0],ack_toggle};data_pipe<={data_pipe[0],serial_bit};
            if(request&&!busy)begin
                req_toggle<=!req_toggle;bits_left<=WIDTH;assemble<=0;elapsed<=0;busy<=1;timed_out<=0;
            end
            if(busy)begin
                if(elapsed<TIMEOUT_CYCLES)elapsed<=elapsed+1'b1;
                else timed_out<=1;
                if(settle!=0)begin
                    settle<=settle-1'b1;
                    if(settle==1)begin
                        assemble<={assemble[WIDTH-2:0],data_pipe[1]};bits_left<=bits_left-1'b1;
                        if(bits_left==1)begin
                            data<={assemble[WIDTH-2:0],data_pipe[1]};snapshot_sequence<=snapshot_sequence+1'b1;valid<=1;busy<=0;
                        end else req_toggle<=!req_toggle;
                    end
                end else if(ack_pipe[1]!=ack_seen)begin ack_seen<=ack_pipe[1];settle<=3;end
            end
        end
    end
endmodule
