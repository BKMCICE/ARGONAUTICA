# A90: attribute DW3 batch/quantization cost on unchanged A61 hardware

Three complete operators: original accepted legacy rolling; unchanged A89
post8 batching under a new namespace; same-source batch loop with raw INT32
readback plus original CPU Q24/bias/leaky/clip. `generate.py` pins A89's complete
header, derives the post copy and proves raw's complete layer function is equal
after reversing only backend namespace, mode enable and finish-call arguments.
The raw finish validates completion/readback, reads at most8 accumulators into
a 32-byte local array, then uses the original quantizer. No production source,
RTL, PDS, model or formal configuration change. No Flash writes.

The raw route intentionally retains post's capability checks and parameter
uploads, to keep the comparison matched on A61; it is not advertised as a
general raw-only optimized driver. On missing post capability, both wrappers
fall back before writes to original legacy rolling, including legacy CTRL alias
0/DONE2; corrupt IDs/busy/fatal/late errors never retry a partial prefix.
CPU quantization requires original fixed-model valid arithmetic ranges. The
post-only overflow rejection test is not imposed on invalid CPU-Q24 inputs.

`run_rtl.py --out F:/... --mode 0|1|2|3 [--sanitize]` drives unchanged actual
post8/raw8/raw4/legacy-only RTL. Each covers327 shapes/offsets/strides/padding,
independent CHW/int64/Q24 outputs, source payload equality, readonly/sentinels,
counts and errors. Both new routes are checked for prewrite rejection and
first/later-task failure without legacy retry. Host time is not target latency.

RV32 main uses the accepted eight geometries, same four DDR comparison buffers,
three warmups and all six orders per geometry. It labels timings explicitly
`control`, `post8`, `raw`. Every result checks independent whole-output hashes,
buffer equality/outside sentinels, readonly inputs and mode reset. Exact SP/CFG,
all instructions/frames/negative checks and a fresh stack guard are required.

After all timed orders for each geometry, two separate untimed repeats read
last-task raw MAC cycles/dots and postprocessor cycles/items. These values
describe only the final row's last task, not total layer cycles. Post mode-off
clears packed_count, so that register is not treated as a retained statistic.
No per-task/per-pixel timers are inserted into either timed operator.

Same-source packing does not force identical compiler register allocation:
backend arguments, readback/store styles, parameter setup and function addresses
remain differences. Whole-operator deltas are comparative evidence, not exact
subtraction of packing/MAC/Q24 stage times. Baseline/post machine words must
match pinned A89 after external-call normalization. Any production optimization
still needs its own whole-image fit, stack, graph, board and scene qualification.

Keep outputs under
`F:/ARGONAUTICA_work/board_tests/20261025_a90_dw3_batch_attribution`.
Restore formal A61+A83 and real dog after measurements, then obtain a new HDMI
OUT observation. HDMI IN is separate; camera remains deferred.
