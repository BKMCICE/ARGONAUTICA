// Single-master MS72xx diagnostic bus. 16-bit register LOW byte first.
// 50MHz / (4*125) = 100kHz. SDA is open drain; every slave ACK is checked.
// No clock stretching or arbitration (SCL is a board diagnostic output).
module hdmi_loop_i2c #(parameter integer Q=125,parameter [7:0] DEVICE=8'hb2)(
 input wire clk, rst_n, start, rd,
 input wire [15:0] address, input wire [7:0] write_data,
 output reg busy, done, error, output reg [7:0] read_data,
 output reg scl, inout wire sda
);
 localparam IDLE=0, START=1, LOW=2, HIGH=3, SAMPLE=4, FALL=5,
 ACK_LOW=6, ACK_HIGH=7, ACK_SAMPLE=8, ACK_FALL=9,
 RESTART_LOW=10, RESTART_HIGH=11, RESTART=12,
 READ_LOW=13, READ_HIGH=14, READ_SAMPLE=15, READ_FALL=16,
 NACK_LOW=17, NACK_HIGH=18, NACK_FALL=19,
 STOP_LOW=20, STOP_HIGH=21, STOP=22;
 reg [4:0] state; reg [15:0] count, addr;
 reg [7:0] data, tx; reg reading, drive_low;
 reg [2:0] bitno; reg [1:0] byte_no;
 assign sda=drive_low ? 1'b0 : 1'bz;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;count<=0;addr<=0;data<=0;tx<=0;reading<=0;
   bitno<=7;byte_no<=0;drive_low<=0;scl<=1;
   busy<=0;done<=0;error<=0;read_data<=0;
  end else begin
   done<=0;
   if(state==IDLE) begin
    count<=0;scl<=1;drive_low<=0;
    if(start) begin
     busy<=1;error<=0;reading<=rd;addr<=address;data<=write_data;
     tx<=DEVICE;byte_no<=0;bitno<=7;read_data<=0;state<=START;
    end
   end else if(count==Q-1) begin
    count<=0;
    case(state)
     START: begin drive_low<=1;state<=LOW;end
     LOW: begin scl<=0;drive_low<=!tx[bitno];state<=HIGH;end
     HIGH: begin scl<=1;state<=SAMPLE;end
     SAMPLE: state<=FALL;
     FALL: begin scl<=0;if(bitno==0)state<=ACK_LOW;
       else begin bitno<=bitno-1'b1;state<=LOW;end end
     ACK_LOW: begin drive_low<=0;state<=ACK_HIGH;end
     ACK_HIGH: begin scl<=1;state<=ACK_SAMPLE;end
     ACK_SAMPLE: begin if(sda)error<=1;state<=ACK_FALL;end
     ACK_FALL: begin
      scl<=0;bitno<=7;
      if(error)state<=STOP_LOW;
      else if(byte_no==0)begin tx<=addr[7:0];byte_no<=1;state<=LOW;end
      else if(byte_no==1)begin tx<=addr[15:8];byte_no<=2;state<=LOW;end
      else if(byte_no==2)begin
       byte_no<=3;
       if(reading)state<=RESTART_LOW;else begin tx<=data;state<=LOW;end
      end else if(reading)state<=READ_LOW;else state<=STOP_LOW;
     end
     RESTART_LOW: begin drive_low<=0;state<=RESTART_HIGH;end
     RESTART_HIGH: begin scl<=1;state<=RESTART;end
     RESTART: begin drive_low<=1;tx<=DEVICE|8'h01;state<=LOW;end
     READ_LOW: begin scl<=0;drive_low<=0;state<=READ_HIGH;end
     READ_HIGH: begin scl<=1;state<=READ_SAMPLE;end
     READ_SAMPLE: begin read_data<={read_data[6:0],sda};state<=READ_FALL;end
     READ_FALL: begin scl<=0;if(bitno==0)state<=NACK_LOW;
       else begin bitno<=bitno-1'b1;state<=READ_LOW;end end
     NACK_LOW: begin drive_low<=0;state<=NACK_HIGH;end
     NACK_HIGH: begin scl<=1;state<=NACK_FALL;end
     NACK_FALL: begin scl<=0;state<=STOP_LOW;end
     STOP_LOW: begin scl<=0;drive_low<=1;state<=STOP_HIGH;end
     STOP_HIGH: begin scl<=1;state<=STOP;end
     STOP: begin drive_low<=0;busy<=0;done<=1;state<=IDLE;end
     default: begin error<=1;state<=STOP_LOW;end
    endcase
   end else count<=count+1'b1;
  end
 end
endmodule
