// pll_sys.v - Logos GTP_PLL_E3 wrapper: 50 MHz in -> CPU_MHZ out (CLKOUT0).
// fout = fin / RATIOI * RATIOF / RATIO0 ; VCO = fin/RATIOI*RATIOF must stay
// in the Logos VCO range (ILIAS reference uses 1187.5 MHz, so ~1 GHz is safe).
// Default: 50/1*20 = 1000 MHz VCO, /10 -> 100 MHz.
module pll_sys #(
    parameter integer RATIOI = 1,
    parameter integer RATIOF = 20,
    parameter integer RATIO0 = 10
)(
    input  wire clkin,
    input  wire rst,       // active high
    output wire clkout0,
    output wire lock
);
    wire clkfb;
    GTP_PLL_E3 #(
        .CLKIN_FREQ(50.0),
        .STATIC_RATIOI(RATIOI), .STATIC_RATIOM(1),
        .STATIC_RATIO0(RATIO0), .STATIC_RATIO1(1), .STATIC_RATIO2(1),
        .STATIC_RATIO3(1), .STATIC_RATIO4(1), .STATIC_RATIOF(RATIOF),
        .INTERNAL_FB("ENABLE"), .EXTERNAL_FB("DISABLE"), .BANDWIDTH("OPTIMIZED")
    ) u_pll (
        .CLKOUT0(clkout0), .CLKOUT0_EXT(), .CLKOUT1(), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .CLKSWITCH_FLAG(), .LOCK(lock),
        .CLKIN1(clkin), .CLKIN2(1'b0), .CLKFB(clkfb), .CLKIN_SEL(1'b1), .CLKIN_SEL_EN(1'b0), .PFDEN(1'b0),
        .ICP_BASE(1'b0), .ICP_SEL(4'b0), .LPFRES_SEL(3'b0), .CRIPPLE_SEL(1'b0),
        .PHASE_SEL(3'b0), .PHASE_DIR(1'b0), .PHASE_STEP_N(1'b0), .LOAD_PHASE(1'b0),
        .RATIOM(7'b0), .RATIOI(10'b0), .RATIO0(10'b0), .RATIO1(10'b0), .RATIO2(10'b0),
        .RATIO3(10'b0), .RATIO4(10'b0), .RATIOF(10'b0),
        .DUTY0(10'b0), .DUTY1(10'b0), .DUTY2(10'b0), .DUTY3(10'b0), .DUTY4(10'b0),
        .CLKOUT0_SYN(1'b0), .CLKOUT0_EXT_SYN(1'b0), .CLKOUT1_SYN(1'b0), .CLKOUT2_SYN(1'b0),
        .CLKOUT3_SYN(1'b0), .CLKOUT4_SYN(1'b0), .CLKOUT5_SYN(1'b0),
        .PLL_PWD(1'b0), .RST(rst), .RSTODIV(1'b0)
    );
    assign clkfb = 1'b0;   // internal feedback
endmodule
