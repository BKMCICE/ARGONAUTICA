// H04S private J clone. Only read2180 adds four-byte RO observation.
// Other addresses/writes retain the original single-byte bus sequence.
// Single-master MS72xx diagnostic bus. 16-bit register LOW byte first.
// 50MHz / (4*125) = 100kHz. SDA is open drain; every slave ACK is checked.
// No clock stretching or arbitration (SCL is a board diagnostic output).
module hdmi_rx_i2c #(parameter integer Q=125)(
 input wire clk, rst_n, start, rd,
 input wire [15:0] address, input wire [7:0] write_data,
 output reg busy, done, error, output reg [7:0] read_data,
 output reg [31:0] observation_data,
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
 reg observation_read;reg [1:0] observation_index;
 reg [7:0] observation_byte;reg [31:0] observation_shadow;
 assign sda=drive_low ? 1'b0 : 1'bz;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;count<=0;addr<=0;data<=0;tx<=0;reading<=0;
   bitno<=7;byte_no<=0;drive_low<=0;scl<=1;
   busy<=0;done<=0;error<=0;read_data<=0;observation_data<=0;
   observation_read<=0;observation_index<=0;observation_byte<=0;observation_shadow<=0;
  end else begin
   done<=0;
   if(state==IDLE) begin
    count<=0;scl<=1;drive_low<=0;
    if(start) begin
     busy<=1;error<=0;reading<=rd;addr<=address;data<=write_data;
     observation_read<=rd&&(address==16'h2180);observation_index<=0;observation_byte<=0;observation_shadow<=0;
     tx<=8'h56;byte_no<=0;bitno<=7;read_data<=0;state<=START;
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
     RESTART: begin drive_low<=1;tx<=8'h57;state<=LOW;end
     READ_LOW: begin scl<=0;drive_low<=0;state<=READ_HIGH;end
     READ_HIGH: begin scl<=1;state<=READ_SAMPLE;end
     READ_SAMPLE: begin
      if(observation_read)observation_byte<={observation_byte[6:0],sda};
      else read_data<={read_data[6:0],sda};
      state<=READ_FALL;
     end
     READ_FALL: begin
      scl<=0;
      if(bitno==0)begin
       if(observation_read)case(observation_index)
        0:observation_shadow[7:0]<=observation_byte;
        1:observation_shadow[15:8]<=observation_byte;
        2:observation_shadow[23:16]<=observation_byte;
        3:observation_shadow[31:24]<=observation_byte;
       endcase
       state<=NACK_LOW;
      end else begin bitno<=bitno-1'b1;state<=READ_LOW;end
     end
     // Observation alone ACKs the first three bytes. Legacy still NACKs one.
     NACK_LOW: begin drive_low<=observation_read&&(observation_index!=3);state<=NACK_HIGH;end
     NACK_HIGH: begin scl<=1;state<=NACK_FALL;end
     NACK_FALL: begin
      scl<=0;
      if(observation_read&&observation_index!=3)begin
       observation_index<=observation_index+1'b1;observation_byte<=0;bitno<=7;state<=READ_LOW;
      end else state<=STOP_LOW;
     end
     STOP_LOW: begin scl<=0;drive_low<=1;state<=STOP_HIGH;end
     STOP_HIGH: begin scl<=1;state<=STOP;end
     STOP: begin
      drive_low<=0;busy<=0;done<=1;state<=IDLE;
      // Preserve last good observation across errors and every legacy access.
      if(observation_read&&reading&&!error)begin observation_data<=observation_shadow;read_data<=observation_shadow[7:0];end
     end
     default: begin error<=1;state<=STOP_LOW;end
    endcase
   end else count<=count+1'b1;
  end
 end
endmodule
