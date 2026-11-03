// H04A isolated UI-clock writer. NOT connected to the production SoC.
// Input records must come from one reset/epoch-qualified async FIFO:
// DATA=0 (32 RGB888 stream bytes, lowest-address byte in bits[7:0]),
// COMMIT=1 (producer validated the *whole* source frame), ABORT=2.
// The producer must NOT send COMMIT on overflow, reset, mode change or short
// frame. This module cannot validate pixels or recover a broken clock domain.
// lease_grant means cache clean+invalidate has finished and CPU access to the
// reserved window is blocked during RECEIVE/WRITE. Keep it asserted until a
// terminal result. PUBLISHED hands a read-only lease to CPU; the slot remains
// owned (cannot start again) until CPU finishes and release_buffer is asserted.
// A line request, once exposed, is held until acknowledgement even on cancel.
// No timeout may abandon that transaction: recovery needs a fabric-wide reset.
module hdmi_frame_line_writer #(
    parameter [31:0] WINDOW_BASE = 32'h80400000,
    parameter [31:0] WINDOW_LIMIT = 32'h80a00000
)(
    input wire clk, rst_n,
    input wire start, lease_grant, cancel, release_buffer,
    input wire [31:0] base_addr, byte_count,
    input wire record_valid,
    output wire record_ready,
    input wire [1:0] record_kind,
    input wire [255:0] record_data,
    output wire line_req,
    output wire line_we,
    output reg [31:0] line_addr,
    output reg [255:0] line_wdata,
    input wire line_ready,
    output wire owned, published, failed,
    output reg [3:0] error_code,
    output reg [31:0] bytes_written
);
    localparam IDLE=0, RECEIVE=1, WRITE=2, PUBLISHED=3, FAILED=4;
    localparam E_RANGE=1, E_LEASE=2, E_CANCEL=3, E_SHORT=4,
               E_EXTRA=5, E_SOURCE=6, E_RECORD=7;
    reg [2:0] state;
    reg [31:0] target_bytes;
    reg [3:0] pending_error;
    wire [32:0] end_addr = {1'b0,base_addr}+{1'b0,byte_count};
    wire range_ok = byte_count != 0 && byte_count[4:0] == 0 &&
        base_addr[4:0] == 0 && base_addr >= WINDOW_BASE &&
        !end_addr[32] && end_addr <= {1'b0,WINDOW_LIMIT};
    assign owned = state != IDLE;
    assign published = state == PUBLISHED;
    assign failed = state == FAILED;
    assign record_ready = state == RECEIVE && lease_grant && !cancel;
    assign line_req = state == WRITE;
    assign line_we = state == WRITE;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; error_code<=0; bytes_written<=0;
            line_addr<=0; line_wdata<=0; target_bytes<=0; pending_error<=0;
        end else case(state)
            IDLE: if(start) begin
                bytes_written<=0; error_code<=0; pending_error<=0;
                target_bytes<=byte_count; line_addr<=base_addr;
                if(!range_ok) begin state<=FAILED; error_code<=E_RANGE; end
                else if(!lease_grant) begin state<=FAILED; error_code<=E_LEASE; end
                else if(cancel) begin state<=FAILED; error_code<=E_CANCEL; end
                else state<=RECEIVE;
            end
            RECEIVE: begin
                if(cancel || !lease_grant) begin
                    state<=FAILED; error_code<=cancel ? E_CANCEL:E_LEASE;
                end else if(record_valid) case(record_kind)
                    0: if(bytes_written == target_bytes) begin
                        state<=FAILED; error_code<=E_EXTRA;
                    end else begin
                        line_wdata<=record_data; pending_error<=0; state<=WRITE;
                    end
                    1: if(bytes_written == target_bytes) state<=PUBLISHED;
                       else begin state<=FAILED; error_code<=E_SHORT; end
                    2: begin state<=FAILED; error_code<=E_SOURCE; end
                    default: begin state<=FAILED; error_code<=E_RECORD; end
                endcase
            end
            WRITE: begin
                // Cancel/grant-loss pulses are sticky until the held line is
                // drained. Neither address nor data changes under backpressure.
                if(pending_error == 0 && (cancel || !lease_grant))
                    pending_error<=cancel ? E_CANCEL:E_LEASE;
                if(line_ready) begin
                    bytes_written<=bytes_written+32;
                    line_addr<=line_addr+32;
                    if(pending_error != 0 || cancel || !lease_grant) begin
                        state<=FAILED;
                        error_code<=pending_error != 0 ? pending_error :
                                    cancel ? E_CANCEL:E_LEASE;
                    end else state<=RECEIVE;
                end
            end
            PUBLISHED,FAILED: if(release_buffer) begin
                state<=IDLE; error_code<=0;
            end
            default: begin state<=FAILED; error_code<=E_RECORD; end
        endcase
    end
endmodule
