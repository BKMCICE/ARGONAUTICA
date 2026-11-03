// H04U private UI-clock boundary: expose ISSUE for legal local slave selects.
// Target fault is decoded from the captured address/selection independently
// of target_req. A request captured by this unit cannot be withdrawn by req-low.
// CPU must defer IRQ while owned and explicitly consume the held response.
module rv_data_transaction_boundary #(parameter SELECT_WIDTH=9)(
    input wire clk,rst_n,
    input wire core_req,core_we,input wire [3:0] core_be,
    input wire [31:0] core_addr,core_wdata,
    input wire [SELECT_WIDTH-1:0] core_sel,
    output wire core_owned,core_ready,core_fault,output wire [31:0] core_rdata,
    input wire core_consume,
    output wire target_req,target_issue,target_we,output wire [3:0] target_be,
    output wire [31:0] target_addr,target_wdata,
    output wire [SELECT_WIDTH-1:0] target_sel,
    input wire target_ready,target_fault,input wire [31:0] target_rdata
);
    localparam [1:0] IDLE=0,ISSUE=1,RESPONSE=2;
    (* syn_preserve=1 *) reg [1:0] state=IDLE;
    (* syn_preserve=1 *) reg [31:0] txn_addr=0,txn_wdata=0;
    (* syn_preserve=1 *) reg [3:0] txn_be=0;
    (* syn_preserve=1 *) reg txn_we=0;
    (* syn_preserve=1 *) reg [SELECT_WIDTH-1:0] txn_sel=0;
    (* syn_preserve=1 *) reg [31:0] response_data=0;
    (* syn_preserve=1 *) reg response_fault=0;
    assign core_owned=state!=IDLE;
    assign core_ready=state==RESPONSE;
    assign core_fault=(state==RESPONSE)&&response_fault;
    assign core_rdata=response_data;
    // Status only: global target_req retains its live fault protection.
    assign target_issue=(state==ISSUE);
    assign target_req=(state==ISSUE)&&!target_fault;
    assign target_we=txn_we;
    assign target_be=txn_be;
    assign target_addr=txn_addr;
    assign target_wdata=txn_wdata;
    assign target_sel=txn_sel;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;txn_addr<=0;txn_wdata<=0;txn_be<=0;txn_we<=0;txn_sel<=0;
            response_data<=0;response_fault<=0;
        end else case(state)
            IDLE: if(core_req)begin
                txn_addr<=core_addr;txn_wdata<=core_wdata;txn_be<=core_be;
                txn_we<=core_we;txn_sel<=core_sel;state<=ISSUE;
            end
            ISSUE: if(target_fault||target_ready)begin
                response_data<=target_fault?32'hdeadbeef:target_rdata;
                response_fault<=target_fault;state<=RESPONSE;
            end
            RESPONSE: if(core_consume)state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
