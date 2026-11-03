// H18 private result mailbox. No DDR access, bus slave, clock or GPIO IRQ added.
// GPIO OUT word: tag[31:29]=101, op[28:25], payload[24:8], legacy LED[7:0].
// UI clock writes a staging transaction. COMMIT copies the entire transaction
// into a held bank, stable until the SYS clock acknowledges its toggle.
// The renderer snapshots the SYS bank at a frame boundary, never per field.
module hdmi_result_mailbox (
    input wire ui_clk, sys_clk, reset_n,
    input wire command_valid,
    input wire [23:0] command,
    output wire busy,
    output reg protocol_error,
    output reg result_valid,
    output reg [2:0] phase,
    output reg [7:0] count,
    output wire [31:0] forward_ms,
    output reg [79:0] classes,
    output reg [99:0] scores
);
    reg stage_open, stage_bad, time_set;
    reg [2:0] stage_phase;
    reg [7:0] stage_count;
    reg [3:0] rows;
    reg [16:0] stage_ms;
    reg [79:0] stage_classes;
    reg [99:0] stage_scores;
    (* syn_preserve=1 *) reg [208:0] held;
    reg request_toggle;
    (* async_reg="true",syn_preserve=1 *) reg [1:0] ack_sync;
    (* async_reg="true",syn_preserve=1 *) reg [1:0] request_sync;
    (* async_reg="true",syn_preserve=1 *) reg [1:0] sys_release;
    reg acknowledge, pending;
    reg [16:0] result_ms;
    wire [3:0] op=command[20:17];
    wire [16:0] payload=command[16:0];
    assign busy=request_toggle!=ack_sync[1];
    assign forward_ms={15'b0,result_ms};
    // Assert reset to both CDC endpoints together, release SYS locally.
    always @(posedge sys_clk or negedge reset_n)
        if(!reset_n)sys_release<=0;else sys_release<={sys_release[0],1'b1};
    always @(posedge ui_clk or negedge reset_n) begin
        if(!reset_n)begin
            ack_sync<=0;stage_open<=0;stage_bad<=0;time_set<=0;
            stage_phase<=0;stage_count<=0;rows<=0;stage_ms<=0;
            stage_classes<=0;stage_scores<=0;held<=0;
            request_toggle<=0;protocol_error<=0;
        end else begin
            ack_sync<={ack_sync[0],acknowledge};
            if(command_valid && command[23:21]==3'b101)begin
                if(busy)protocol_error<=1;
                else if(op==4'd14 && payload==0)begin
                    stage_open<=1;stage_bad<=0;protocol_error<=0;time_set<=0;
                    stage_phase<=0;stage_count<=0;rows<=0;stage_ms<=0;
                    stage_classes<=0;stage_scores<=0;
                end else if(!stage_open)protocol_error<=1;
                else case(op)
                    4'd0:if(payload<=4)stage_phase<=payload[2:0];
                         else begin stage_bad<=1;protocol_error<=1;end
                    4'd1:if(rows<10 && payload[16:10]<80 && payload[9:0]<=1000)begin
                        stage_classes[rows*8+:8]<={1'b0,payload[16:10]};
                        stage_scores[rows*10+:10]<=payload[9:0];rows<=rows+1'b1;
                    end else begin stage_bad<=1;protocol_error<=1;end
                    4'd2:begin stage_ms<=payload;time_set<=1;end
                    4'd3:if(payload<=10)stage_count<=payload[7:0];
                         else begin stage_bad<=1;protocol_error<=1;end
                    // Error code remains in UART; the page truthfully says ERROR.
                    4'd4:begin stage_phase<=4;stage_count<=0;rows<=0;end
                    4'd15:begin
                        stage_open<=0;
                        if(payload!=0 || stage_bad ||
                           (stage_phase==3 && (stage_count!={4'b0,rows} || !time_set)) ||
                           (stage_phase!=3 && (stage_count!=0 || rows!=0)))
                            protocol_error<=1;
                        else begin
                            held<={1'b1,stage_phase,stage_count,stage_ms,stage_classes,stage_scores};
                            request_toggle<=~request_toggle;
                        end
                    end
                    default:begin stage_bad<=1;protocol_error<=1;end
                endcase
            end
        end
    end
    // Two-flop request synchronizer plus an extra settling cycle. The UI bank
    // cannot change from COMMIT until acknowledge traverses its two-flop return.
    always @(posedge sys_clk or negedge sys_release[1]) begin
        if(!sys_release[1])begin
            request_sync<=0;acknowledge<=0;pending<=0;
            result_valid<=0;phase<=0;count<=0;result_ms<=0;classes<=0;scores<=0;
        end else begin
            request_sync<={request_sync[0],request_toggle};
            if(pending)begin
                {result_valid,phase,count,result_ms,classes,scores}<=held;
                acknowledge<=request_sync[1];pending<=0;
            end else if(request_sync[1]!=acknowledge)pending<=1;
        end
    end
endmodule
