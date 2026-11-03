# A97 optional production separable pooling, cached DDR placement

YOLO_POOL_SEPARABLE defaults0 and accepts only0/1 in C and Make. The original
maxpool body is untouched. The reject-before-write fixed-model helper is
body-identical to A93, with one separately owned100B aligned DDR scratch.
Shapes/Q24 outside its supported domain retain the original generic pool.
There is no partially processed failure or retry. Nonoverlapping valid and
stable tensors remain the original caller contract, not a new alias scan.

In the formal TCM/RGB3-stack build the helper joins the existing .ddr_rgb3
cached-DDR code region (which already includes non-RGB cold code). Generic
other builds use normal .text. No linker or TCM capacity expansion. Actual
whole-image proof must cover the cross-region call and GCC's constprop clone.
Default/flag0 BIN must equal A92; enabled profile/plain BINs must match.

run_host.py compiles actual production control/placebo flag0 and candidate1.
1536 fixed full operators,18 raw-helper rejection cases,70 generic fallback
cases, broad INT8/negative Q24, readonly/sentinels and ASan/UBSan are checked.
Host counters prove fast1536/fallback70, not accidental generic execution.
run_graph.py checks six frames in six capability/sanitizer modes, every byte
of131 tensors, exact detections/traffic, three actual fast pool calls and the
existing identity-forward domain rejection. Host MMIO remains mathematical.

Makefile builds a separate cold-DDR operator diagnostic using A96's unchanged
main/control/placebo/expected outputs and this production helper. Logs retain
A96 fixture labels. No new performance claim is imported from the all-TCM
A96 diagnostic. New target ELF/stack/call/scratch and negative audits precede
three physical operator configurations; production image has separate audits
and three real dog runs/legacy fallback, before independent scene adoption.

check_contract.py proves the helper body is unchanged and removing only the
new flag/inclusion/dispatch restores the previous entire main.c byte-for-byte
after newline normalization. Neither production helper nor old maxpool uses
the diagnostic's expected arrays. All output remains fixed-model compatible.
