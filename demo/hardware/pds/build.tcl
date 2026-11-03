set hardware [file normalize [file join [file dirname [info script]] ..]]
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
add_design [file join $hardware build_src ip ddr3_pangu50k ddr3_test.idf]
source [file join $hardware pds selected_sources.tcl]
add_constraint [file join $hardware inputs capture.fdc]
set root [file join $hardware build_src]
set boot [file join $hardware inputs boot.hex]
compile -loop_limit 1000000 -compiler_directives SYNTHESIS -top_module pangu50k_capture_top -include_path [list $root/rtl/core $root/tools/board_diag/hdmi_rx_phase] -defined_parameters [list RAM_INIT_FILE "\"$boot\""]
synthesize -ads -rw_check_on_ram -selected_syn_tool_opt 2
dev_map
pnr -plc_decongestion 3 -mode performance -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_threshold 100 -fix_hold_violation_threshold_for_clk_tree 100 -fix_hold_violation_threshold_for_clock_path_cross_srb 0 -fix_hold_violation_iterations 12 -gplace_seed 14 -groute_seed 23 -generate_bitstream FALSE -enable_route_constraint_iterate -route_constraint_iterate_times 2 -route_constraint_slack 0.0 -route_constraint_max_timing_path 1
report_timing -delay_type min_max -max_path 64 -nworst 1 -report_exception TRUE
gen_netlist -func_sim_only -sdf_annotate FALSE
exit
