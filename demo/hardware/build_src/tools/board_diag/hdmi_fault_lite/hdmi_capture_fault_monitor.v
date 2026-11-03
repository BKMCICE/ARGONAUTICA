// H04W minimal observer only. No output changes capture/DDR/reset/ownership.
// PIX first code survives FIFO epoch cleanup. A launch ARM/ACK gives diagnostic
// identity, and a frozen 16-bit serial snapshot transfers code/valid/armed/token.
// No XY/pixel/native-wait counters, wide bundle CDC or frontend ABI change.
module hdmi_capture_fault_monitor #(
    parameter integer SNAPSHOT_TIMEOUT_CYCLES=1000000
)(
    input wire clk,pix_clk,rst_n,launch,input wire [31:0] job_sequence,
    input wire dma_lease,invalid_record,input wire [1:0] invalid_record_kind,
    input wire [7:0] pix_fault,input wire fifo_up,
    input wire req,we,input wire [3:0] be,input wire [11:0] addr,
    input wire [31:0] wdata,output wire ready,output wire [31:0] rdata
);
    reg arm_request=0,arm_overrun=0,job_seen=0;
    reg [31:0] current_job=0;
    (* async_reg="true",syn_preserve=1 *) reg [1:0] pix_release=0;
    always @(posedge pix_clk or negedge rst_n)
        if(!rst_n)pix_release<=0;else pix_release<={pix_release[0],1'b1};
    wire pix_diag_rst_n=pix_release[1];
    (* async_reg="true",syn_preserve=1 *) reg [1:0] arm_pipe=0;
    reg arm_ack=0,pix_armed=0,pix_fault_valid=0;
    reg [7:0] held_code=0;
    always @(posedge pix_clk or negedge pix_diag_rst_n)begin
        if(!pix_diag_rst_n)begin
            arm_pipe<=0;arm_ack<=0;pix_armed<=0;pix_fault_valid<=0;held_code<=0;
        end else begin
            arm_pipe<={arm_pipe[0],arm_request};
            if(arm_pipe[1]!=arm_ack)begin
                // Reset diagnostics only. Already-visible current epoch fault
                // must survive ARM; dead FIFO epoch faults are not admitted.
                arm_ack<=arm_pipe[1];pix_armed<=1;
                pix_fault_valid<=fifo_up&&(|pix_fault);
                held_code<=fifo_up&&pix_fault!=0 ? pix_fault : 8'b0;
            end else if(pix_armed&&!pix_fault_valid&&fifo_up&&pix_fault!=0)begin
                pix_fault_valid<=1;held_code<=pix_fault;
            end
        end
    end
    (* async_reg="true",syn_preserve=1 *) reg [1:0] ack_pipe=0;
    wire arm_pending=arm_request!=ack_pipe[1];
    always @(posedge clk or negedge rst_n)
        if(!rst_n)ack_pipe<=0;else ack_pipe<={ack_pipe[0],arm_ack};
    reg invalid_seen=0;reg [1:0] invalid_kind=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            arm_request<=0;arm_overrun<=0;job_seen<=0;current_job<=0;
            invalid_seen<=0;invalid_kind<=0;
        end else if(launch)begin
            current_job<=job_sequence;job_seen<=1;
            if(arm_pending)arm_overrun<=1;
            else begin arm_request<=!arm_request;arm_overrun<=0;end
            invalid_seen<=0;invalid_kind<=0;
        end else if(dma_lease&&invalid_record&&!invalid_seen)begin
            invalid_seen<=1;invalid_kind<=invalid_record_kind;
        end
    end
    wire [15:0] pix_packet={5'b0,arm_ack,pix_armed,pix_fault_valid,held_code};
    reg response=0;reg [31:0] read_result=0;
    reg snapshot_pending=0,snapshot_valid=0;
    reg [31:0] snapshot_sequence=0,snapshot_job=0;
    reg [17:0] snapshot_flags=0;
    reg [31:0] request_job=0;
    reg request_arm=0,request_identity_allowed=0,request_pending=0,request_overrun=0;
    reg request_invalid=0;reg [1:0] request_kind=0;
    wire serial_busy,serial_valid,serial_timeout;wire [31:0] serial_sequence;
    wire [15:0] serial_data;
    wire accept_snapshot=req&&!response&&we&&be==4'hf&&addr==12'h07c&&wdata==1&&
                         !snapshot_pending&&!serial_busy;
    hdmi_frontend_snapshot #(.WIDTH(16),.TIMEOUT_CYCLES(SNAPSHOT_TIMEOUT_CYCLES)) pix_snapshot(
        .sys_clk(pix_clk),.ui_clk(clk),.reset_n(rst_n),.source_data(pix_packet),.request(accept_snapshot),
        .busy(serial_busy),.valid(serial_valid),.timed_out(serial_timeout),
        .snapshot_sequence(serial_sequence),.data(serial_data));
    wire identity_ok=request_identity_allowed&&!launch&&job_seen&&!arm_pending&&!arm_overrun&&
                     request_job==current_job&&request_arm==arm_request&&serial_data[9]&&serial_data[10]==request_arm;
    wire current_snapshot_match=snapshot_valid&&snapshot_flags[12]&&snapshot_job==current_job&&
                                !arm_pending&&!arm_overrun&&job_seen;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            snapshot_pending<=0;snapshot_valid<=0;snapshot_sequence<=0;snapshot_job<=0;snapshot_flags<=0;
            request_job<=0;request_arm<=0;request_identity_allowed<=0;
            request_pending<=0;request_overrun<=0;request_invalid<=0;request_kind<=0;
        end else begin
            if(launch)snapshot_valid<=0;
            if(accept_snapshot)begin
                snapshot_pending<=1;snapshot_valid<=0;
                request_job<=current_job;request_arm<=arm_request;
                request_identity_allowed<=job_seen&&!launch&&!arm_pending&&!arm_overrun;
                request_pending<=arm_pending;request_overrun<=arm_overrun;
                request_invalid<=invalid_seen;request_kind<=invalid_kind;
            end
            // snapshot_sequence is the last copied serial_sequence. A stale
            // serial_valid cannot republish the old packet on a new request.
            // Only one request is pending; increment/wrap is owned by serial.
            if(snapshot_pending&&serial_valid&&serial_sequence!=snapshot_sequence)begin
                snapshot_pending<=0;snapshot_valid<=1;snapshot_sequence<=serial_sequence;
                snapshot_job<=request_job;
                snapshot_flags<={request_kind,request_invalid,request_overrun,request_pending,
                                 identity_ok,request_arm,serial_data[10:0]};
            end
        end
    end
    reg [31:0] decoded;
    always @*begin
        case(addr)
            12'h070:decoded=32'h48303457;
            12'h074:decoded={26'b0,current_snapshot_match,arm_overrun,arm_pending,serial_timeout,
                            snapshot_valid,(snapshot_pending||serial_busy)};
            12'h078:decoded=snapshot_sequence;
            12'h07c:decoded=0;
            12'h080:decoded=snapshot_job;
            12'h084:decoded={14'b0,snapshot_flags};
            default:decoded=32'hdeadbeef;
        endcase
    end
    assign ready=req&&response;assign rdata=read_result;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin response<=0;read_result<=0;end
        else if(response)response<=0;
        else if(req)begin response<=1;read_result<=decoded;end
    end
endmodule
