# A49 isolated post8 physical candidate. Existing build scripts keep their gates.
# This is never selected by run_pds.ps1 or a default/formal build.
if {![info exists ::env(RV32_POST8_EXPERIMENT)] || $::env(RV32_POST8_EXPERIMENT) ne "1"} {
    error "RV32_POST8_EXPERIMENT=1 is required for the isolated A49 candidate"
}
foreach {flag expected} {
    RV32_AI_BLOCK 1 RV32_AI_BLOCK8 1 RV32_AI_QUANT 1 RV32_AI_WINDOW 0
    RV32_BTB 1 RV32_CACHE_STATS_SPLIT 0 RV32_ICACHE_DRM 1
    RV32_DCACHE_TAG_STORAGE 2 RV32_REGFILE_STORAGE 1
    RV32_PNR_SEED 13 RV32_PNR_ROUTE_SEED 23
    RV32_RAM_IMAGE bootloader_ddr_100mhz_115200.hex
} {
    if {[info exists ::env($flag)] && $::env($flag) ne $expected} {
        error "A49 fixed recipe requires $flag=$expected"
    }
}
set post8_map_only 0
if {[info exists ::env(RV32_POST8_MAP_ONLY)]} { set post8_map_only $::env(RV32_POST8_MAP_ONLY) }
if {$post8_map_only ni {0 1}} { error "RV32_POST8_MAP_ONLY must be 0 or 1" }
if {![info exists ::env(RV32_ILA_FIC)] || ![file exists $::env(RV32_ILA_FIC)]} {
    error "RV32_ILA_FIC must name the separately bound A44-equivalent probe file"
}
set root [file normalize [file join [file dirname [info script]] ..]]
set ram_image [file normalize [file join $root firmware bootloader_ddr_100mhz_115200.hex]]
if {![file exists $ram_image]} { error "DDR boot image missing: $ram_image" }

set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
add_design [file join $root ip ddr3_pangu50k ddr3_test.idf]
add_sources -design -sub_directories $root/rtl
add_constraint $root/constr/pangu50k_ddr.fdc
add_constraint $root/constr/pangu50k_hdmi.fdc
add_fic $::env(RV32_ILA_FIC)
compile -loop_limit 1000000 -compiler_directives SYNTHESIS -top_module pangu50k_ddr_top -include_path [list $root/rtl/core] -defined_parameters [list RAM_INIT_FILE "\"$ram_image\"" ENABLE_BTB 1 ENABLE_AI_BLOCK 1 ENABLE_AI_QUANT 1 ENABLE_AI_BLOCK8 1 CACHE_STATS_SPLIT_COUNTERS 0 ICACHE_DRM 1 DCACHE_TAG_STORAGE 2 REGFILE_STORAGE 1]
synthesize -ads -rw_check_on_ram -selected_syn_tool_opt 2
dev_map
if {!$post8_map_only} {
    pnr -plc_decongestion 3 -mode performance -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold 50 -fix_hold_violation_threshold_for_clk_tree 50 -fix_hold_violation_threshold_for_clock_path_cross_srb 50 -fix_hold_violation_iterations 20 -gplace_seed 13 -groute_seed 23
    report_timing -delay_type min_max -max_path 10 -nworst 3 -report_exception TRUE
    gen_bit_stream
    gen_netlist -func_sim_only -sdf_annotate FALSE
}
