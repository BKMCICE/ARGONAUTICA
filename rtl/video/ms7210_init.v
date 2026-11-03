// MS7210 HDMI transmitter setup on the MES50HP board.
// Register addresses/data follow the board package's 05_hdmi_test/ms7210_ctl.v.
// Bus sequencing is independent of that example: four-byte I2C writes,
// open-drain SDA and an ACK check on every transmitted byte.
module ms7210_init #(
    parameter integer QUARTER_CYCLES = 125,    // Three phases/bit: about 133 kHz at 50 MHz
    parameter integer RESET_CYCLES = 50000,    // 1 ms after configuration
    parameter integer WRITE_GAP_CYCLES = 50000,
    parameter integer SETTLE_CYCLES = 16000000 // 320 ms after command 18
)(
    input  wire clk,
    input  wire rst_n,
    output wire hdmi_rst_n,
    output reg  scl,
    inout  wire sda,
    output reg  init_done,
    output reg  init_error
);
    localparam [3:0] RESET = 0, START = 1, BIT_LOW = 2,
                     BIT_HIGH = 3, ACK_LOW = 4, ACK_HIGH = 5,
                     STOP_LOW = 6, STOP_HIGH = 7, STOP_RELEASE = 8,
                     GAP = 9, DONE = 10, FAIL = 11,
                     BIT_FALL = 12, ACK_SAMPLE = 13;
    reg [3:0] state = RESET;
    reg sda_low = 0;
    assign sda = sda_low ? 1'b0 : 1'bz;
    assign hdmi_rst_n = rst_n && state != RESET;
    reg [31:0] wait_count = 0;
    reg [31:0] phase_count = 0;
    reg [5:0] command_index = 0;
    reg [1:0] byte_index = 0;
    reg [2:0] bit_index = 7;
    reg [7:0] tx_byte = 0;
    reg nack = 0;

    function [23:0] command;
        input [5:0] index;
        begin
            case (index)
                0: command=24'h128104;  1: command=24'h001604;
                2: command=24'h000901;  3: command=24'h000709;
                4: command=24'h0008f0;  5: command=24'h000af0;
                6: command=24'h000611;  7: command=24'h053184;
                8: command=24'h090020;  9: command=24'h090147;
               10: command=24'h090409; 11: command=24'h092307;
               12: command=24'h092444; 13: command=24'h092544;
               14: command=24'h090f80; 15: command=24'h091f07;
               16: command=24'h09201e; 17: command=24'h001820;
               18: command=24'h05c0fe; 19: command=24'h000b00;
               20: command=24'h050706; 21: command=24'h090604;
               22: command=24'h09205e; 23: command=24'h0926dd;
               24: command=24'h09270d; 25: command=24'h092888;
               26: command=24'h092908; 27: command=24'h091001;
               28: command=24'h000b11; 29: command=24'h050e00;
               30: command=24'h050a82; 31: command=24'h050902;
               32: command=24'h050b0d; 33: command=24'h050d06;
               34: command=24'h050d11; 35: command=24'h050d58;
               36: command=24'h050d00; 37: command=24'h050d00;
               38: command=24'h050d00; 39: command=24'h050d00;
               40: command=24'h050d00; 41: command=24'h050d00;
               42: command=24'h050d00; 43: command=24'h050d00;
               44: command=24'h050d00; 45: command=24'h050d00;
               46: command=24'h050d00; 47: command=24'h050e40;
               48: command=24'h050700;
               default: command=24'h000000;
            endcase
        end
    endfunction

    function [7:0] next_byte;
        input [5:0] index;
        input [1:0] number;
        reg [23:0] word;
        begin
            word = command(index);
            case (number)
                0: next_byte = 8'hb2; // 7-bit address 0x59, write
                // MS7210 uses register LOW byte first (board iic_dri.v),
                // even though the command table is written address:data.
                1: next_byte = word[15:8];
                2: next_byte = word[23:16];
                default: next_byte = word[7:0];
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RESET;
            scl <= 1;
            sda_low <= 0;
            init_done <= 0;
            init_error <= 0;
            wait_count <= 0;
            phase_count <= 0;
            command_index <= 0;
            byte_index <= 0;
            bit_index <= 7;
            tx_byte <= 0;
            nack <= 0;
        end else if (state == RESET) begin
            scl <= 1;
            sda_low <= 0;
            if (wait_count == RESET_CYCLES-1) begin
                wait_count <= 0;
                state <= START;
            end else wait_count <= wait_count + 1'b1;
        end else if (state == GAP) begin
            scl <= 1;
            sda_low <= 0;
            if (wait_count == ((command_index == 6'd19) ? SETTLE_CYCLES : WRITE_GAP_CYCLES)-1) begin
                wait_count <= 0;
                state <= START;
            end else wait_count <= wait_count + 1'b1;
        end else if (state != DONE && state != FAIL) begin
            if (phase_count == QUARTER_CYCLES-1) begin
                phase_count <= 0;
                case (state)
                    START: begin
                        scl <= 1;
                        sda_low <= 1;
                        byte_index <= 0;
                        bit_index <= 7;
                        tx_byte <= next_byte(command_index, 0);
                        nack <= 0;
                        state <= BIT_LOW;
                    end
                    BIT_LOW: begin
                        scl <= 0;
                        sda_low <= !tx_byte[bit_index];
                        state <= BIT_HIGH;
                    end
                    BIT_HIGH: begin
                        scl <= 1;
                        state <= BIT_FALL;
                    end
                    BIT_FALL: begin
                        scl <= 0;
                        if (bit_index == 0) state <= ACK_LOW;
                        else begin
                            bit_index <= bit_index - 1'b1;
                            state <= BIT_LOW;
                        end
                    end
                    ACK_LOW: begin
                        scl <= 0;
                        sda_low <= 0;
                        state <= ACK_HIGH;
                    end
                    ACK_HIGH: begin
                        scl <= 1;
                        state <= ACK_SAMPLE;
                    end
                    ACK_SAMPLE: begin
                        scl <= 0;
                        if (sda) nack <= 1;
                        if (byte_index == 3 || sda) state <= STOP_LOW;
                        else begin
                            byte_index <= byte_index + 1'b1;
                            tx_byte <= next_byte(command_index, byte_index + 1'b1);
                            bit_index <= 7;
                            state <= BIT_LOW;
                        end
                    end
                    STOP_LOW: begin
                        scl <= 0;
                        sda_low <= 1;
                        state <= STOP_HIGH;
                    end
                    STOP_HIGH: begin
                        scl <= 1;
                        state <= STOP_RELEASE;
                    end
                    STOP_RELEASE: begin
                        sda_low <= 0;
                        if (nack) begin
                            init_error <= 1;
                            state <= FAIL;
                        end else if (command_index == 6'd48) begin
                            init_done <= 1;
                            state <= DONE;
                        end else begin
                            command_index <= command_index + 1'b1;
                            wait_count <= 0;
                            state <= GAP;
                        end
                    end
                    default: state <= FAIL;
                endcase
            end else phase_count <= phase_count + 1'b1;
        end
    end
endmodule
