# PDS build for the cached DDR3 SoC. Run from an ASCII project directory.
set root [file normalize [file join [file dirname [info script]] ..]]
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
add_design [file join $root ip ddr3_pangu50k ddr3_test.idf]
add_sources -design -sub_directories $root/rtl
add_constraint $root/constr/pangu50k_ddr.fdc
add_constraint $root/constr/pangu50k_hdmi.fdc
set image_name ddr_selftest_100mhz.hex
if {[info exists ::env(RV32_RAM_IMAGE)]} { set image_name $::env(RV32_RAM_IMAGE) }
if {[lsearch -exact {hello_100mhz_115200.hex ddr_selftest_100mhz.hex bootloader_ddr_100mhz_115200.hex} $image_name] < 0} {
    error "Unsupported DDR boot image: $image_name"
}
set ram_image [file normalize [file join $root firmware $image_name]]
if {![file exists $ram_image]} { error "DDR boot image missing: $ram_image" }
set enable_btb 1
if {[info exists ::env(RV32_BTB)]} { set enable_btb $::env(RV32_BTB) }
if {$enable_btb ni {0 1}} { error "RV32_BTB must be 0 or 1" }
set enable_ai_block 0
if {[info exists ::env(RV32_AI_BLOCK)]} { set enable_ai_block $::env(RV32_AI_BLOCK) }
if {$enable_ai_block ni {0 1}} { error "RV32_AI_BLOCK must be 0 or 1" }
set enable_ai_quant 0
if {[info exists ::env(RV32_AI_QUANT)]} { set enable_ai_quant $::env(RV32_AI_QUANT) }
if {$enable_ai_quant ni {0 1} || ($enable_ai_quant && !$enable_ai_block)} { error "RV32_AI_QUANT requires block mode and must be 0 or 1" }
set enable_ai_block8 0
if {[info exists ::env(RV32_AI_BLOCK8)]} { set enable_ai_block8 $::env(RV32_AI_BLOCK8) }
if {$enable_ai_block8 ni {0 1} || ($enable_ai_block8 && (!$enable_ai_block || $enable_ai_quant))} { error "RV32_AI_BLOCK8 requires block=1, quant=0 and must be 0 or 1" }
set dcache_tag_storage 0
if {[info exists ::env(RV32_DCACHE_TAG_STORAGE)]} { set dcache_tag_storage $::env(RV32_DCACHE_TAG_STORAGE) }
if {$dcache_tag_storage ni {0 1 2}} { error "RV32_DCACHE_TAG_STORAGE must be 0, 1 or 2" }
set regfile_storage 0
if {[info exists ::env(RV32_REGFILE_STORAGE)]} { set regfile_storage $::env(RV32_REGFILE_STORAGE) }
if {$regfile_storage ni {0 1}} { error "RV32_REGFILE_STORAGE must be 0 or 1" }
compile -loop_limit 1000000 -compiler_directives SYNTHESIS -top_module pangu50k_ddr_top -include_path [list $root/rtl/core] -defined_parameters [list RAM_INIT_FILE "\"$ram_image\"" ENABLE_BTB $enable_btb ENABLE_AI_BLOCK $enable_ai_block ENABLE_AI_QUANT $enable_ai_quant ENABLE_AI_BLOCK8 $enable_ai_block8 DCACHE_TAG_STORAGE $dcache_tag_storage REGFILE_STORAGE $regfile_storage]
if {![info exists ::env(RV32_COMPILE_ONLY)] || $::env(RV32_COMPILE_ONLY) ne "1"} {
    synthesize -ads -rw_check_on_ram -selected_syn_tool_opt 2
    dev_map
    set pnr_args [list -plc_decongestion 3 -mode performance -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_threshold 0 -fix_hold_violation_threshold_for_clk_tree 0 -fix_hold_violation_threshold_for_clock_path_cross_srb 0 -fix_hold_violation_iterations 12]
    if {[info exists ::env(RV32_PNR_SEED)] && $::env(RV32_PNR_SEED) ne ""} {
        lappend pnr_args -gplace_seed $::env(RV32_PNR_SEED)
        if {![info exists ::env(RV32_PNR_ROUTE_SEED)] || $::env(RV32_PNR_ROUTE_SEED) eq ""} {
            lappend pnr_args -groute_seed $::env(RV32_PNR_SEED)
        }
    }
    if {[info exists ::env(RV32_PNR_ROUTE_SEED)] && $::env(RV32_PNR_ROUTE_SEED) ne ""} {
        lappend pnr_args -groute_seed $::env(RV32_PNR_ROUTE_SEED)
    }
    pnr {*}$pnr_args
    report_timing
    gen_bit_stream
    gen_netlist -func_sim_only -sdf_annotate FALSE
}
