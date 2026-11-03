// H04Z private RAW320 memory subsystem; full1080p source qualification.
// Original writer/mux/bridge/cache/lease/protection behavior is retained.
// Actual A61 cache backends + DDR bridge;
// isolated from production SoC/top/PDS. CPU ports are blocking DDR word ports;
// connect I through the existing imem_cache_adapter, D through soc_bus.
// Control is an independent MMIO slave at proposed 0x40006000 (low12 decoded).
// Real CPU/SoC/board integration remains a separate acceptance step.
module hdmi_frame_memory #(
    parameter integer EXPECT_W=1920,EXPECT_H=1080,FIFO_ADDR_BITS=9,
    parameter integer TIMEOUT_CYCLES=100000000
)(
    input wire clk,pix_clk,rst_n,pix_reset_n,ddr_init_done,
    input wire cpu_i_req,input wire [31:0] cpu_i_addr,
    output wire [31:0] cpu_i_rdata,output wire cpu_i_ready,
    input wire cpu_d_req,cpu_d_we,input wire [3:0] cpu_d_be,
    input wire [31:0] cpu_d_addr,cpu_d_wdata,
    output wire [31:0] cpu_d_rdata,output wire cpu_d_ready,cpu_d_fault,
    input wire fence_req,output wire fence_done,
    input wire ctrl_req,ctrl_we,input wire [3:0] ctrl_be,
    input wire [31:0] ctrl_addr,ctrl_wdata,
    output reg [31:0] ctrl_rdata,output wire ctrl_ready,
    input wire de,hs,vs,input wire [23:0] rgb,
    input wire fault_req,fault_we,input wire [3:0] fault_be,
    input wire [11:0] fault_addr,input wire [31:0] fault_wdata,
    output wire fault_ready,output wire [31:0] fault_rdata,
    output wire cpu_block,dma_lease,frame_valid,frame_owned,job_busy,
    output wire i_hit,i_miss,d_hit,d_miss,
    output wire [27:0] axi_awaddr,axi_araddr,
    output wire axi_awuser_ap,axi_aruser_ap,
    output wire [3:0] axi_awuser_id,axi_aruser_id,axi_awlen,axi_arlen,
    input wire axi_awready,axi_arready,axi_wready,
    output wire axi_awvalid,axi_arvalid,
    output wire [255:0] axi_wdata,output wire [31:0] axi_wstrb,
    input wire [255:0] axi_rdata,input wire axi_rvalid,axi_rlast
);
    localparam [31:0] BASE=32'h80400000,LIMIT=32'h80a00000;
    // Source qualification dimensions MUST NOT be reused as output dimensions.
    localparam integer OUTPUT_W=320,OUTPUT_H=320;
    localparam [31:0] OUTPUT_BYTES=32'd307200;
    localparam [31:0] BYTES=OUTPUT_BYTES;
    localparam IDLE=0,QUIET=1,CLEAN=2,INVALIDATE=3,SWITCH=4,ARM=5,
               CAPTURE=6,DRAIN=7,READONLY=8,FAILED=9,RELEASE_WAIT=10,
               RELEASE_PULSE=11,RELEASE_ACK=12,FENCE_ACK=13;
    reg [3:0] state=0,return_state=0;
    reg maintenance_only=0,cancel_pending=0,valid_frame=0,launched_this_job=0;
    reg [7:0] job_error=0,command_error=0;
    reg [31:0] sequence_number=0;
    wire terminal=state==READONLY||state==FAILED;
    wire normal=state==IDLE||terminal;
    // Six new read-only identity words ignore every write byte-enable/data value.
    // Preserve the original invalid-command behavior for every other address.
    wire model_identity_address=(ctrl_addr[11:0]==12'h090)||(ctrl_addr[11:0]==12'h094)||
        (ctrl_addr[11:0]==12'h098)||(ctrl_addr[11:0]==12'h09c)||
        (ctrl_addr[11:0]==12'h0a0)||(ctrl_addr[11:0]==12'h0a4);
    wire write_command=ctrl_req&&ctrl_we&&!model_identity_address;
    wire command_format=ctrl_addr[11:0]==0&&ctrl_be==4'hf;
    wire start_command=write_command&&command_format&&ctrl_wdata==1;
    wire cancel_command=write_command&&command_format&&ctrl_wdata==2;
    wire release_command=write_command&&command_format&&ctrl_wdata==4;
    wire maintenance_begin=normal&&fence_req;
    wire accept_start=start_command&&state==IDLE&&!fence_req;
    wire accept_release=release_command&&terminal&&!fence_req;
    wire accept_cancel=cancel_command&&!maintenance_only&&state>=QUIET&&state<=DRAIN;
    wire abort_job=cancel_pending||accept_cancel;
    assign cpu_block=!normal||maintenance_begin||accept_start||accept_release;
    assign dma_lease=state==ARM||state==CAPTURE||state==DRAIN;
    assign frame_valid=valid_frame;
    assign frame_owned=state!=IDLE;
    assign job_busy=!normal;
    assign fence_done=state==FENCE_ACK;
    assign ctrl_ready=ctrl_req;

    wire i_inflight,d_inflight;
    reg i_pending=0,d_pending=0;
    assign i_inflight=i_pending;assign d_inflight=d_pending;
    // Exact aligned 6 MiB reservation: [80400000,80800000) plus
    // [80800000,80a00000). No lower address bits enter protection decode.
    wire frame_access=cpu_d_addr[31:22]==10'h201 || cpu_d_addr[31:21]==11'h404;
    // FREE/IDLE permits setup writes; published frame has a CPU read-only
    // lease. Failed slot cannot expose partial pixels until explicit release.
    wire denied=frame_access&&(state==FAILED||(state==READONLY&&cpu_d_we));
    wire i_accept=cpu_i_req&&!cpu_block&&!i_pending;
    wire d_accept=cpu_d_req&&!cpu_block&&!d_pending&&!denied;
    wire i_done,d_done;
    wire [31:0] i_word,d_word;
    assign cpu_i_rdata=i_word;
    assign cpu_i_ready=i_pending&&i_done;
    // Fault classifies address + registered policy, even when req is suppressed
    // by rv_core's trap. Do NOT depend on cpu_block: it includes ctrl_req and
    // fence_req, which themselves depend on the core's trap-suppressed commit.
    // A terminal-state command can block completion without changing this
    // classification. During maintenance/drain the registered state is neither
    // READONLY nor FAILED, so new requests wait without an access fault.
    assign cpu_d_fault=!d_pending&&denied;
    assign cpu_d_ready=(d_pending&&d_done)||(cpu_d_req&&!cpu_block&&cpu_d_fault);
    assign cpu_d_rdata=cpu_d_fault?32'hdeadbeef:d_word;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin i_pending<=0;d_pending<=0;end
        else begin
            if(i_accept) i_pending<=1;
            else if(i_pending&&i_done) i_pending<=0;
            if(d_accept) d_pending<=1;
            else if(d_pending&&d_done) d_pending<=0;
        end
    end
    wire il_req,il_we,il_ready,dl_req,dl_we,dl_ready,clean_done;
    wire [31:0] il_addr,dl_addr;
    wire [255:0] il_wdata,dl_wdata,line_rdata;
    rv_icache_drm #(.EARLY_READ(1)) icache(
        .clk(clk),.rst_n(rst_n),.invalidate(state==INVALIDATE),.flush_req(1'b0),.flush_done(),
        .cpu_req(i_accept),.cpu_addr(cpu_i_addr),.cpu_rdata(i_word),.cpu_ready(i_done),
        .hit_event(i_hit),.miss_event(i_miss),.line_req(il_req),.line_we(il_we),.line_addr(il_addr),
        .line_wdata(il_wdata),.line_rdata(line_rdata),.line_ready(il_ready));
    rv_cache_2way #(.TAG_STORAGE(2)) dcache(
        .clk(clk),.rst_n(rst_n),.invalidate(state==INVALIDATE),.flush_req(state==CLEAN),.flush_done(clean_done),
        .cpu_req(d_accept),.cpu_we(cpu_d_we),.cpu_be(cpu_d_be),.cpu_addr(cpu_d_addr),.cpu_wdata(cpu_d_wdata),
        .cpu_rdata(d_word),.cpu_ready(d_done),.hit_event(d_hit),.miss_event(d_miss),
        .line_req(dl_req),.line_we(dl_we),.line_addr(dl_addr),.line_wdata(dl_wdata),
        .line_rdata(line_rdata),.line_ready(dl_ready));
    wire record_valid,record_ready,t_owned,t_done,t_failed,t_cancel;
    wire [1:0] record_kind;wire [255:0] record_data;
    wire [7:0] transport_error;
    wire [7:0] observe_pix_fault;wire observe_fifo_up,observe_invalid_record;
    wire [1:0] observe_record_kind;
    wire w_owned,w_published,w_failed,write_req,write_ready;
    wire [31:0] write_addr,bytes_written;wire [255:0] write_data;
    wire [3:0] writer_error;
    wire launch=state==ARM&&!abort_job;
    wire release_all=state==RELEASE_PULSE;
    hdmi_frame_transport #(.EXPECT_W(EXPECT_W),.EXPECT_H(EXPECT_H),
        .FIFO_ADDR_BITS(FIFO_ADDR_BITS),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) transport(
        .sys_clk(clk),.pix_clk(pix_clk),.sys_rst_n(rst_n),.pix_reset_n(pix_reset_n),
        .start(launch),.cancel(abort_job||w_failed),.release_epoch(release_all),.downstream_drained(1'b1),
        .de(de),.hs(hs),.vs(vs),.rgb(rgb),.record_valid(record_valid),.record_ready(record_ready),
        .record_kind(record_kind),.record_data(record_data),.owned(t_owned),.done(t_done),.failed(t_failed),
        .writer_cancel(t_cancel),.error_code(transport_error),
        .observe_pix_fault(observe_pix_fault),.observe_fifo_up(observe_fifo_up),
        .observe_invalid_record(observe_invalid_record),.observe_record_kind(observe_record_kind));
    hdmi_frame_line_writer writer(
        .clk(clk),.rst_n(rst_n),.start(launch),.lease_grant(dma_lease),
        .cancel(abort_job||t_cancel),.release_buffer(release_all),.base_addr(BASE),.byte_count(BYTES),
        .record_valid(record_valid),.record_ready(record_ready),.record_kind(record_kind),.record_data(record_data),
        .line_req(write_req),.line_we(),.line_addr(write_addr),.line_wdata(write_data),.line_ready(write_ready),
        .owned(w_owned),.published(w_published),.failed(w_failed),.error_code(writer_error),.bytes_written(bytes_written));
    wire mux_idle,line_req,line_we,line_ready;
    wire [31:0] line_addr;wire [255:0] line_wdata;
    hdmi_frame_line_mux mux(
        .clk(clk),.rst_n(rst_n),.dma_lease(dma_lease),
        .i_req(il_req),.i_addr(il_addr),.i_ready(il_ready),
        .d_req(dl_req),.d_we(dl_we),.d_addr(dl_addr),.d_wdata(dl_wdata),.d_ready(dl_ready),
        .dma_req(write_req),.dma_addr(write_addr),.dma_wdata(write_data),.dma_ready(write_ready),
        .idle(mux_idle),.mem_req(line_req),.mem_we(line_we),.mem_addr(line_addr),.mem_wdata(line_wdata),.mem_ready(line_ready));
    ddr3_line_bridge bridge(
        .clk(clk),.rst_n(rst_n),.ddr_init_done(ddr_init_done),
        .line_req(line_req),.line_we(line_we),.line_addr(line_addr),.line_wdata(line_wdata),
        .line_rdata(line_rdata),.line_ready(line_ready),
        .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awuser_ap),.axi_awuser_id(axi_awuser_id),
        .axi_awlen(axi_awlen),.axi_awready(axi_awready),.axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),
        .axi_araddr(axi_araddr),.axi_aruser_ap(axi_aruser_ap),.axi_aruser_id(axi_aruser_id),
        .axi_arlen(axi_arlen),.axi_arready(axi_arready),.axi_arvalid(axi_arvalid),
        .axi_rdata(axi_rdata),.axi_rvalid(axi_rvalid),.axi_rlast(axi_rlast));
    // Parallel W diagnostics never feed control, reset, lease or native handshake.
    hdmi_capture_fault_monitor fault_monitor(
        .clk(clk),.pix_clk(pix_clk),.rst_n(rst_n),.launch(launch),.job_sequence(sequence_number),
        .dma_lease(dma_lease),.invalid_record(observe_invalid_record),.invalid_record_kind(observe_record_kind),
        .pix_fault(observe_pix_fault),.fifo_up(observe_fifo_up),
        .req(fault_req),.we(fault_we),.be(fault_be),.addr(fault_addr),.wdata(fault_wdata),
        .ready(fault_ready),.rdata(fault_rdata));
    wire cpu_drained=!i_inflight&&!d_inflight&&mux_idle;
    wire writer_terminal=!w_owned||w_published||w_failed;
    wire transport_terminal=!t_owned||t_done||t_failed;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;return_state<=IDLE;maintenance_only<=0;cancel_pending<=0;
            valid_frame<=0;job_error<=0;command_error<=0;sequence_number<=0;launched_this_job<=0;
        end else begin
            if(launch)launched_this_job<=1;
            if(write_command) begin
                if(accept_start||accept_release||accept_cancel) command_error<=0;
                else command_error<=command_format?8'h01:8'h02;
            end
            if(accept_cancel) cancel_pending<=1;
            case(state)
                IDLE,READONLY,FAILED: begin
                    if(maintenance_begin) begin
                        maintenance_only<=1;return_state<=state;state<=QUIET;
                    end else if(accept_start) begin
                        maintenance_only<=0;cancel_pending<=0;valid_frame<=0;job_error<=0;launched_this_job<=0;
                        sequence_number<=sequence_number+1'b1;state<=QUIET;
                    end else if(accept_release) begin valid_frame<=0;state<=RELEASE_WAIT;end
                end
                QUIET: if(cpu_drained) begin
                    if(abort_job&&!maintenance_only) begin state<=FAILED;job_error<=1;end
                    else state<=CLEAN;
                end
                CLEAN: if(clean_done) state<=INVALIDATE;
                INVALIDATE: if(maintenance_only) state<=FENCE_ACK;else state<=SWITCH;
                FENCE_ACK: begin state<=return_state;maintenance_only<=0;end
                SWITCH: if(mux_idle) begin
                    if(abort_job) begin state<=FAILED;job_error<=1;end
                    else state<=ARM;
                end
                ARM: if(abort_job) state<=DRAIN;else state<=CAPTURE;
                CAPTURE: if(abort_job||t_failed||w_failed||(w_published&&t_done)) state<=DRAIN;
                DRAIN: if(mux_idle&&writer_terminal&&transport_terminal) begin
                    if(!abort_job&&w_published&&t_done&&!w_failed&&!t_failed) begin
                        valid_frame<=1;state<=READONLY;
                    end else begin
                        valid_frame<=0;job_error<=abort_job?8'h01:8'h02;state<=FAILED;
                    end
                end
                RELEASE_WAIT: if(cpu_drained) state<=RELEASE_PULSE;
                RELEASE_PULSE: state<=RELEASE_ACK;
                RELEASE_ACK: if(!w_owned&&!t_owned) begin state<=IDLE;cancel_pending<=0;end
                default: begin state<=FAILED;valid_frame<=0;job_error<=8'hff;end
            endcase
        end
    end
    always @(*) begin
        case(ctrl_addr[11:0])
            12'h000:ctrl_rdata=32'h48304331;
            12'h004:ctrl_rdata={16'b0,4'b0,state,command_error!=0,dma_lease,cpu_block,frame_owned,
                               state==FAILED,frame_valid,job_busy,1'b0};
            12'h008:ctrl_rdata=BASE;
            12'h00c:ctrl_rdata=BYTES;
            12'h010:ctrl_rdata=launched_this_job?bytes_written:32'b0;
            12'h014:ctrl_rdata={command_error,job_error,launched_this_job?transport_error:8'b0,
                               4'b0,launched_this_job?writer_error:4'b0};
            12'h018:ctrl_rdata=sequence_number;
            // Z identity is outside the inherited T (+20..6c) and W (+70..84) windows.
            12'h090:ctrl_rdata=32'h4830345a; // H04Z
            12'h094:ctrl_rdata=32'd1;       // NN_CENTER_RAW320_V1
            12'h098:ctrl_rdata=32'h04380780;// source H=1080, W=1920
            12'h09c:ctrl_rdata=32'h01400140;// output H=320, W=320
            12'h0a0:ctrl_rdata=32'd1;       // RGB888_INTERLEAVED_RAW
            12'h0a4:ctrl_rdata=32'd1;       // ABI version
            default:ctrl_rdata=32'hdeadbeef;
        endcase
    end
`ifndef SYNTHESIS
    initial begin
        if(EXPECT_W!=1920||EXPECT_H!=1080)
            $fatal(1,"H04Z memory requires complete1920x1080 source geometry");
        if(OUTPUT_W!=320||OUTPUT_H!=320||BYTES!=307200||
           BYTES!=OUTPUT_W*OUTPUT_H*3||BYTES[4:0]!=0||BYTES>LIMIT-BASE)
            $fatal(1,"unsupported H04Z RAW320 output geometry");
    end
`endif
endmodule
