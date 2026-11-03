# PDS 2022.2 batch flow. Run through run_pds.ps1; output defaults to pds/project.
# Resolve sources from this script, independent of the checkout drive or cwd.
set root [file normalize [file join [file dirname [info script]] ..]]
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
add_sources -design -sub_directories $root/rtl
add_constraint $root/constr/pangu50k.fdc
set image_name hello_100mhz_115200.hex
if {[info exists ::env(RV32_RAM_IMAGE)]} { set image_name $::env(RV32_RAM_IMAGE) }
if {[lsearch -exact {hello_100mhz_115200.hex coremark_100mhz_115200_2000.hex} $image_name] < 0} {
    error "Unsupported board RAM image: $image_name"
}
set ram_image [file normalize [file join $root firmware $image_name]]
if {![file exists $ram_image]} { error "Board RAM image missing: $ram_image" }
set enable_btb 0
if {[info exists ::env(RV32_BTB)]} { set enable_btb $::env(RV32_BTB) }
if {$enable_btb ni {0 1}} { error "RV32_BTB must be 0 or 1" }
compile -loop_limit 1000000 -compiler_directives SYNTHESIS -top_module pangu50k_top -include_path [list $root/rtl/core] -defined_parameters [list RAM_INIT_FILE "\"$ram_image\"" ENABLE_M 1 ENABLE_BTB $enable_btb RAM_ADDR_W 14]
if {![info exists ::env(RV32_COMPILE_ONLY)] || $::env(RV32_COMPILE_ONLY) ne "1"} {
    synthesize -ads -rw_check_on_ram -selected_syn_tool_opt 2
    dev_map
    pnr -plc_decongestion 3 -mode {performance} -optimize_multi_corner_timing -fix_hold_violation
    report_timing
    gen_bit_stream
}
