# A96 isolated RV32 separable-pool diagnostic

control/placebo each include the unchanged actual production main.c and call
its maxpool_layer. Candidate includes the unchanged A93 prototype.h. No
production dispatch, RTL/PDS, model or current_board_configuration changes.
All three code copies are in the same TCM image, no ICF or computed dispatch.
Actual ELF verifies two distinct byte-identical original pool implementations
and byte-identical control/placebo wrappers; candidate guards are timed too.

Twelve cases: kernels3/5/9 from actual layers109/111/113, each full10x10x48,
patterns signed byte ramp, negative-only, all-128, signed modulo255 ramp.
Case offset is pattern0..3 for input/output/scratch; host tests separately
exercise all4 offsets across broad patterns. One output buffer and one input
buffer are reused at identical addresses by every variant. Before each call,
outside the timer, all containers and the input are reset in the same order;
each geometry has a warmup per variant, followed by all six variant orders.
Seventy-two triples/configuration, three independent SRAM configurations.

Every timed call checks all4800 expected bytes from independent 2D/Python
int64/division references, independent FNV, full readonly input and outside
sentinels. Candidate scratch is one caller-owned100B payload in a separate
132B DDR container reused per channel; no production/global scratch reuse is
assumed. Original/placebo must leave even its payload unchanged. Eighteen
unsupported/null/size cases reject before output/scratch writes.

run_host.py compiles the same wrappers for native normal and ASan/UBSan:
1536 full operators each, original/placebo/candidate vs independent 2D oracle,
all INT8 constants plus extremes, deterministic random and offsets/guards.
generate_expected.py --check verifies the exact target output arrays.

Required before board: actual ELF/image/model-free layout, closed SP/CFG/
direct calls/one-trap stack audit and negative mutations, DDR object ownership,
control/placebo code identity, profile/plain same BIN, source/hash binding.
Then three board configurations; finally restore current formal A61+A92 and
run real dog, verify detections/TCM/guard and get a fresh display observation.

Local RV32 operator cycles do not imply whole-model speed. Diagnostic code
and stack sizes do not prove production integration fits its remaining168B.
No full-model candidate or adopted pool implementation is created here.
