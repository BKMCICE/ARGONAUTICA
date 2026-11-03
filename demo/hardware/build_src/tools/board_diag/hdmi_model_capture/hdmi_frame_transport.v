// H04Z private RAW320 transport, inherited W epoch/fault/ownership unchanged.
// EXPECT_W/H qualify the full source1080p; producer emits fixed RAW320 records.
// One accepted start owns an epoch until terminal + downstream_drained release.
// sys_rst_n is a TRANSACTION-FABRIC reset (writer/bridge/controller together).
// pix_reset_n is source-only: abort epoch, cancel writer, NEVER reset writer.
module hdmi_frame_transport #(
    parameter integer EXPECT_W=1920,EXPECT_H=1080,FIFO_ADDR_BITS=9,
    parameter integer TIMEOUT_CYCLES=100000000
)(
    input wire sys_clk,pix_clk,sys_rst_n,pix_reset_n,
    input wire start,cancel,release_epoch,downstream_drained,
    input wire de,hs,vs,input wire [23:0] rgb,
    output wire record_valid,input wire record_ready,
    output wire [1:0] record_kind,output wire [255:0] record_data,
    output wire owned,done,failed,writer_cancel,
    output reg [7:0] error_code,
    output wire [7:0] observe_pix_fault,output wire observe_fifo_up,
    output wire observe_invalid_record,output wire [1:0] observe_record_kind
);
    localparam IDLE=0,CLEAR=1,WAIT_UP=2,RUN=3,DONE=4,FAILED=5;
    reg [2:0] state=0;
    reg [31:0] elapsed=0;
    reg [2:0] clear_count=0;
    wire fifo_enable=state==WAIT_UP||state==RUN;
    wire epoch_rst_n=sys_rst_n&&pix_reset_n&&fifo_enable;
    wire producer_valid,producer_ready,w_up,r_up;
    wire [257:0] producer_record,fifo_record;
    wire fifo_valid,fifo_ready;
    wire [7:0] producer_fault;
    // W observation taps only; original state/reset/record logic is unchanged.
    assign observe_pix_fault=producer_fault;assign observe_fifo_up=w_up;
    assign observe_invalid_record=record_valid&&record_ready&&(record_kind==2||record_kind==3);
    assign observe_record_kind=record_kind;
    (* async_reg="true",syn_preserve=1 *) reg [1:0] w_up_sync=0;
    // Transfer a sticky fault BIT. Encoded PIX fault stays local/diagnostic;
    // no unsafely sampled multi-bit fault value qualifies a frame.
    (* async_reg="true",syn_preserve=1 *) reg [1:0] fault_sync=0;
    // Async-set event latch catches a short PIX reset between SYS edges.
    // Clear only with reset released while IDLE/CLEAR, before epoch starts.
    reg pix_reset_seen=0;
    always @(posedge sys_clk or negedge pix_reset_n)
        if(!pix_reset_n) pix_reset_seen<=1;
        else if(!sys_rst_n||state==IDLE||state==CLEAR) pix_reset_seen<=0;
    wire active=state==WAIT_UP||state==RUN;
    wire timeout=active&&elapsed>=TIMEOUT_CYCLES-1;
    wire unsafe_epoch=!pix_reset_n||pix_reset_seen||fault_sync[1]||cancel||timeout;
    assign owned=state!=IDLE;
    assign done=state==DONE;
    assign failed=state==FAILED;
    assign writer_cancel=failed||(active&&unsafe_epoch);
    assign record_valid=state==RUN&&!unsafe_epoch&&fifo_valid;
    assign fifo_ready=state==RUN&&!unsafe_epoch&&record_ready;
    assign record_kind=fifo_record[257:256];
    assign record_data=fifo_record[255:0];
    hdmi_frame_rx_producer #(.EXPECT_W(EXPECT_W),.EXPECT_H(EXPECT_H)) producer(
        // Same shared epoch assertion, but release ONLY on the PIX clock.
        // Gating enable alone does not protect asynchronous reset recovery.
        .pix_clk(pix_clk),.rst_n(w_up),.enable(w_up),
        .de(de),.hs(hs),.vs(vs),.rgb(rgb),
        .record_valid(producer_valid),.record_ready(producer_ready),
        .record(producer_record),.fault(producer_fault));
    hdmi_frame_async_fifo #(.ADDR_BITS(FIFO_ADDR_BITS)) fifo(
        .rst_n(epoch_rst_n),.wclk(pix_clk),.rclk(sys_clk),
        .wvalid(producer_valid),.wready(producer_ready),.wdata(producer_record),
        .rvalid(fifo_valid),.rready(fifo_ready),.rdata(fifo_record),.w_up(w_up),.r_up(r_up));
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            state<=IDLE;elapsed<=0;clear_count<=0;error_code<=0;
            w_up_sync<=0;fault_sync<=0;
        end else begin
            w_up_sync<={w_up_sync[0],w_up};
            fault_sync<={fault_sync[0],|producer_fault};
            case(state)
                IDLE: if(start) begin
                    state<=CLEAR;clear_count<=0;elapsed<=0;error_code<=0;
                end
                CLEAR: if(!pix_reset_n||cancel) begin
                    state<=FAILED;error_code<=cancel?8'h20:8'h40;
                end else if(clear_count==3) begin
                    state<=WAIT_UP;elapsed<=0;
                end else clear_count<=clear_count+1'b1;
                WAIT_UP,RUN: begin
                    elapsed<=elapsed+1'b1;
                    if(unsafe_epoch) begin
                        state<=FAILED;
                        error_code<=cancel?8'h20:
                            (!pix_reset_n||pix_reset_seen)?8'h40:
                            fault_sync[1]?8'h80:8'h04;
                    end else if(state==WAIT_UP) begin
                        if(w_up_sync[1]&&r_up) state<=RUN;
                    end else if(record_valid&&record_ready) begin
                        if(record_kind==1) state<=DONE;
                        else if(record_kind!=0) begin state<=FAILED;error_code<=8'h80;end
                    end
                end
                DONE,FAILED: if(release_epoch&&downstream_drained) state<=IDLE;
                default: begin state<=FAILED;error_code<=8'hff;end
            endcase
        end
    end
`ifndef SYNTHESIS
    initial if(EXPECT_W!=1920||EXPECT_H!=1080)
        $fatal(1,"H04Z transport requires complete1920x1080 source geometry");
`endif
endmodule
