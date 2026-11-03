`timescale 1ns/1ps
module  ddr3_test #(

   parameter DFI_CLK_PERIOD       = 10000         ,

   parameter MEM_ROW_WIDTH   = 15         ,

   parameter MEM_COLUMN_WIDTH   = 10         ,

   parameter MEM_BANK_WIDTH      = 3          ,

  parameter MEM_DQ_WIDTH         =  32         ,

  parameter MEM_DM_WIDTH         =  4         ,

  parameter MEM_DQS_WIDTH        =  4         ,

  parameter REGION_NUM           =  3         ,

  parameter CTRL_ADDR_WIDTH      = MEM_ROW_WIDTH + MEM_COLUMN_WIDTH + MEM_BANK_WIDTH         
  )(
   input                              ref_clk        ,
   input                              resetn         ,
   output                             ddr_init_done  ,
   output                             ddrphy_clkin   ,
   output                             pll_lock       , 
 
   input [CTRL_ADDR_WIDTH-1:0]        axi_awaddr     ,
   input                              axi_awuser_ap  ,
   input [3:0]                        axi_awuser_id  ,
   input [3:0]                        axi_awlen      ,
   output                             axi_awready    ,
   input                              axi_awvalid    ,

   input [MEM_DQ_WIDTH*8-1:0]         axi_wdata      ,
   input [MEM_DQ_WIDTH-1:0]           axi_wstrb      ,
   output                             axi_wready     ,
   output [3:0]                       axi_wusero_id  ,
   output                             axi_wusero_last,

   input [CTRL_ADDR_WIDTH-1:0]        axi_araddr     ,
   input                              axi_aruser_ap  ,
   input [3:0]                        axi_aruser_id  ,
   input [3:0]                        axi_arlen      ,
   output                             axi_arready    ,
   input                              axi_arvalid    ,

   output[8*MEM_DQ_WIDTH-1:0]         axi_rdata      ,
   output[3:0]                        axi_rid        ,
   output                             axi_rlast      ,
   output                             axi_rvalid     ,

   input                              apb_clk        ,
   input                              apb_rst_n      ,
   input                              apb_sel        ,
   input                              apb_enable     ,
   input [7:0]                        apb_addr       ,
   input                              apb_write      ,
   output                             apb_ready      ,
   input [15:0]                       apb_wdata      ,
   output[15:0]                       apb_rdata      ,
   output                             apb_int        ,
   output [34*MEM_DQS_WIDTH -1:0]     debug_data           ,
   output [13*MEM_DQS_WIDTH -1:0]     debug_slice_state    ,
   output [21:0]                      debug_calib_ctrl     ,
   output [7:0]                       ck_dly_set_bin       ,
   input                              force_ck_dly_en      ,
   input [7:0]                        force_ck_dly_set_bin ,
   output [7:0]                       dll_step             ,    
   output                             dll_lock             ,
   input [1:0]                        init_read_clk_ctrl   ,                                                       
   input [3:0]                        init_slip_step       ,                                                
   input                              force_read_clk_ctrl  , 

   input                              ddrphy_gate_update_en,
   output [MEM_DQS_WIDTH-1:0]         update_com_val_err_flag,
   input                              rd_fake_stop         ,
   
   output                             mem_rst_n            ,                       
   output                             mem_ck               ,
   output                             mem_ck_n             ,
   output                             mem_cke              ,

   output                             mem_cs_n             ,

   output                             mem_ras_n            ,
   output                             mem_cas_n            ,
   output                             mem_we_n             , 
   output                             mem_odt              ,
   output [MEM_ROW_WIDTH-1:0]         mem_a                ,   
   output [MEM_BANK_WIDTH-1:0]        mem_ba               ,   
   inout [MEM_DQS_WIDTH-1:0]          mem_dqs              ,
   inout [MEM_DQS_WIDTH-1:0]          mem_dqs_n            ,
   inout [MEM_DQ_WIDTH-1:0]           mem_dq               ,
   output [MEM_DM_WIDTH-1:0]          mem_dm               
);
// Simulation-only native RAM boundary. PDS MUST use real IDF, never this file.
reg ui=0;always #5 ui=~ui;
assign ddrphy_clkin=ui;assign pll_lock=resetn;assign ddr_init_done=resetn;
capture_sparse_native_model model(
 .clk(ui),.rst_n(resetn),.axi_awaddr(axi_awaddr),.axi_awlen(axi_awlen),.axi_awvalid(axi_awvalid),.axi_awready(axi_awready),
 .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),
 .axi_araddr(axi_araddr),.axi_arlen(axi_arlen),.axi_arvalid(axi_arvalid),.axi_arready(axi_arready),
 .axi_rdata(axi_rdata),.axi_rvalid(axi_rvalid),.axi_rlast(axi_rlast));
assign axi_rid=0;assign axi_wusero_id=0;assign axi_wusero_last=axi_wready;
assign mem_rst_n=resetn;assign mem_ck=0;assign mem_ck_n=1;assign mem_cke=0;assign mem_cs_n=1;
assign mem_ras_n=1;assign mem_cas_n=1;assign mem_we_n=1;assign mem_odt=0;assign mem_a=0;assign mem_ba=0;assign mem_dm=0;
assign apb_ready=0;assign apb_rdata=0;assign apb_int=0;assign debug_data=0;assign debug_slice_state=0;
assign debug_calib_ctrl=0;assign ck_dly_set_bin=0;assign dll_step=0;assign dll_lock=0;assign update_com_val_err_flag=0;
endmodule

// Sparse, checked address model for this 16x8 board-boundary test only.
// Native addresses are32bit word units; no truncation alias into scratch RAM.
module capture_sparse_native_model(
 input wire clk,rst_n,input wire [27:0] axi_awaddr,axi_araddr,
 input wire [3:0] axi_awlen,axi_arlen,input wire axi_awvalid,axi_arvalid,
 output wire axi_awready,axi_arready,input wire [255:0] axi_wdata,
 input wire [31:0] axi_wstrb,output wire axi_wready,
 output reg [255:0] axi_rdata,output reg axi_rvalid,axi_rlast
);
 reg [255:0] scratch[0:2047],frame[0:11];
 reg wr=0,rd=0;reg [2:0] wc=0,rc=0;reg [27:0] wa=0,ra=0;
 integer n,b;
 initial begin for(n=0;n<2048;n=n+1)scratch[n]=0;for(n=0;n<12;n=n+1)frame[n]=0;end
 assign axi_awready=!wr;assign axi_arready=!rd;assign axi_wready=wr&&wc==0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin wr<=0;rd<=0;wc<=0;rc<=0;wa<=0;ra<=0;axi_rvalid<=0;axi_rlast<=0;axi_rdata<=0;end
  else begin
   axi_rvalid<=0;axi_rlast<=0;
   if(axi_awvalid&&axi_awready)begin
    if(axi_awlen!=0||axi_awaddr[2:0]!=0)$fatal(1,"sparse AW shape");
    wr<=1;wa<=axi_awaddr;wc<=2;
   end else if(wr&&wc!=0)wc<=wc-1'b1;
   else if(axi_wready)begin
    if(axi_wstrb!=32'hffffffff)$fatal(1,"sparse full strobe");
    if(wa<28'h4000)scratch[wa>>3]<=axi_wdata;
    else if(wa>=28'h100000&&wa<28'h100060)frame[(wa-28'h100000)>>3]<=axi_wdata;
    else $fatal(1,"sparse DDR write bounds %h",wa);
    wr<=0;
   end
   if(axi_arvalid&&axi_arready)begin
    if(axi_arlen!=0||axi_araddr[2:0]!=0)$fatal(1,"sparse AR shape");
    rd<=1;ra<=axi_araddr;rc<=3;
   end else if(rd&&rc!=0)rc<=rc-1'b1;
   else if(rd)begin
    if(ra<28'h4000)axi_rdata<=scratch[ra>>3];
    else if(ra>=28'h100000&&ra<28'h100060)axi_rdata<=frame[(ra-28'h100000)>>3];
    else $fatal(1,"sparse DDR read bounds %h",ra);
    axi_rvalid<=1;axi_rlast<=1;rd<=0;
   end
  end
 end
endmodule
