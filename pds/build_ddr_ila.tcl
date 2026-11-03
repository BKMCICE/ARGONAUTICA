# Independent DDR/HDMI Fabric Inserter build. Do not overwrite the S11 image.
set root [file normalize [file join [file dirname [info script]] ..]]
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
add_design [file join $root ip ddr3_pangu50k ddr3_test.idf]
add_sources -design -sub_directories $root/rtl
add_constraint $root/constr/pangu50k_ddr.fdc
add_constraint $root/constr/pangu50k_hdmi.fdc
if {![info exists ::env(RV32_ILA_FIC)]} { error "RV32_ILA_FIC is required" }
add_fic $::env(RV32_ILA_FIC)
set image_name bootloader_ddr_100mhz_115200.hex
set ram_image [file normalize [file join $root firmware $image_name]]
if {![file exists $ram_image]} { error "DDR boot image missing: $ram_image" }
set enable_ai_block 0
if {[info exists ::env(RV32_AI_BLOCK)]} { set enable_ai_block $::env(RV32_AI_BLOCK) }
if {$enable_ai_block ni {0 1}} { error "RV32_AI_BLOCK must be 0 or 1" }
set enable_ai_quant 0
if {[info exists ::env(RV32_AI_QUANT)]} { set enable_ai_quant $::env(RV32_AI_QUANT) }
if {$enable_ai_quant ni {0 1} || ($enable_ai_quant && !$enable_ai_block)} { error "RV32_AI_QUANT requires block mode and must be 0 or 1" }
set enable_ai_block8 0
if {[info exists ::env(RV32_AI_BLOCK8)]} { set enable_ai_block8 $::env(RV32_AI_BLOCK8) }
if {$enable_ai_block8 ni {0 1} || ($enable_ai_block8 && (!$enable_ai_block || $enable_ai_quant))} { error "RV32_AI_BLOCK8 requires block=1, quant=0 and must be 0 or 1" }
set cache_stats_split 0
if {[info exists ::env(RV32_CACHE_STATS_SPLIT)]} { set cache_stats_split $::env(RV32_CACHE_STATS_SPLIT) }
if {$cache_stats_split ni {0 1}} { error "RV32_CACHE_STATS_SPLIT must be 0 or 1" }
set icache_drm 0
if {[info exists ::env(RV32_ICACHE_DRM)]} { set icache_drm $::env(RV32_ICACHE_DRM) }
if {$icache_drm ni {0 1}} { error "RV32_ICACHE_DRM must be 0 or 1" }
set icache_early_read 0
if {[info exists ::env(RV32_ICACHE_EARLY_READ)]} { set icache_early_read $::env(RV32_ICACHE_EARLY_READ) }
if {$icache_early_read ni {0 1}} { error "RV32_ICACHE_EARLY_READ must be 0 or 1" }
if {$icache_early_read && !$icache_drm} { error "RV32_ICACHE_EARLY_READ requires RV32_ICACHE_DRM=1" }
set dcache_tag_storage 0
if {[info exists ::env(RV32_DCACHE_TAG_STORAGE)]} { set dcache_tag_storage $::env(RV32_DCACHE_TAG_STORAGE) }
if {$dcache_tag_storage ni {0 1 2}} { error "RV32_DCACHE_TAG_STORAGE must be 0, 1 or 2" }
set regfile_storage 0
if {[info exists ::env(RV32_REGFILE_STORAGE)]} { set regfile_storage $::env(RV32_REGFILE_STORAGE) }
if {$regfile_storage ni {0 1}} { error "RV32_REGFILE_STORAGE must be 0 or 1" }
set pipeline_probe 0
if {[info exists ::env(RV32_PIPELINE_PROBE)]} { set pipeline_probe $::env(RV32_PIPELINE_PROBE) }
if {$pipeline_probe ni {0 1}} { error "RV32_PIPELINE_PROBE must be 0 or 1" }
set pipeline_defines [list SYNTHESIS]
if {$pipeline_probe} { lappend pipeline_defines RV32_PIPELINE_PROBE_KEEP }
compile -loop_limit 1000000 -compiler_directives $pipeline_defines -top_module pangu50k_ddr_top -include_path [list $root/rtl/core] -defined_parameters [list RAM_INIT_FILE "\"$ram_image\"" ENABLE_BTB 1 ENABLE_AI_BLOCK $enable_ai_block ENABLE_AI_QUANT $enable_ai_quant ENABLE_AI_BLOCK8 $enable_ai_block8 CACHE_STATS_SPLIT_COUNTERS $cache_stats_split ICACHE_DRM $icache_drm ICACHE_EARLY_READ $icache_early_read DCACHE_TAG_STORAGE $dcache_tag_storage REGFILE_STORAGE $regfile_storage ENABLE_PIPELINE_PROBE $pipeline_probe]
synthesize -ads -rw_check_on_ram -selected_syn_tool_opt 2
dev_map
set pnr_args [list -plc_decongestion 3 -mode performance -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold 50 -fix_hold_violation_threshold_for_clk_tree 50 -fix_hold_violation_threshold_for_clock_path_cross_srb 50 -fix_hold_violation_iterations 20]
set place_seed 13
set route_seed 23
if {[info exists ::env(RV32_PNR_SEED)] && $::env(RV32_PNR_SEED) ne ""} { set place_seed $::env(RV32_PNR_SEED) }
if {[info exists ::env(RV32_PNR_ROUTE_SEED)] && $::env(RV32_PNR_ROUTE_SEED) ne ""} { set route_seed $::env(RV32_PNR_ROUTE_SEED) }
lappend pnr_args -gplace_seed $place_seed -groute_seed $route_seed
pnr {*}$pnr_args
report_timing
gen_bit_stream
gen_netlist -func_sim_only -sdf_annotate FALSE
