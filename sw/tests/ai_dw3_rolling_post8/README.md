# A89: original DW3 row rolling with existing post8 hardware

This is an isolated software experiment. Production source, RTL, PDS and the
formal A61+A83 configuration are unchanged. No new accelerator or DMA is added.
The candidate keeps the accepted 24-bit three-row rolling representation for
interior pixels, including stride1/2 and continuation across eight-pixel tasks.
Border pixels use coordinate-based zero padding. Input windows are not rebuilt
into intermediate tensor/strip buffers. Shared hardware does Q24/bias/leaky/clip
and returns packed INT8. Only full/aligned words use the existing alias-safe
store helper; other outputs use bytes. Descriptor and readonly tensors must
remain stable, output must not cover descriptor metadata, and legacy bias must
be initialized to zero as in the accepted application.

`generate.py` pins the complete accepted rolling header, copies its exact
shape/span/tensor-overlap validator into the new transport, and produces an
exact namespace-only original control. `candidate_body.inc` explicitly contains
the new batching/control loop; it is not claimed to be a mechanical one-line
rewrite. `candidate.c` wraps only prewrite unsupported with the original operator.
Capability corruption, busy, timeout, task/quant error and late readback errors
never fall back. The caller discards the entire layer on those fatal errors.
The original legacy operator retains its original unbounded DONE contract; the
new block path polls at most100000 times per task. They are distinct contracts.

On legacy-only RTL, 0x100 aliases CTRL. Idle 0 and DONE2 must both be recognized
as unsupported before writes; busy/unknown values are errors. Raw8/raw4 hardware
without post8 also uses the original rolling operator, before block writes.

`run_rtl.py --out F:/... --mode 0|1|2|3 [--sanitize]` compiles native C with
fixture-only hooks and drives unchanged actual RTL. Modes are post8, raw8,
raw4 and legacy-only. Compare independent int64 CHW/Q24 output, whole buffers,
readonly tensors, original-vs-placebo complete legacy traces and exact flattened
pixel/weight payloads between original and new tasks. Task/readback counts,
capability/busy/shape/alias rejection, first/later-task timeout/error/late error,
missing parameters and quant overflow are checked. Host cycles are not RV32 or
physical timing. ASan/UBSan supplement exact-span and sentinel tests.

The RV32 diagnostic uses three separate translation units, no ICF/jump tables,
the same four DDR buffers, eight geometry rows, three warmups and all six
control/placebo/candidate orders per geometry. It checks independent expected
hashes, equality/sentinels, readonly tensors, raw-mode restoration and stack
guard. Eight sizes include real160x160x8/80x80x32/40x40x48, stride2, cropped
padding/tails, tiny shapes and offset input. This is complete-operator timing,
not a whole-model or AP/FPS result. Reaudit exact ELF/SP/CFG/frames and temporary
full-image fit before any broader integration; the production hot area has
only216B spare. Do not expand its budget based on the diagnostic fit.

All outputs go under
`F:/ARGONAUTICA_work/board_tests/20261025_a89_dw3_rolling_post8`.
Restore the hash-bound formal A61+A83 and a real dog inference after measurements,
then request a fresh display observation. No Flash programming.
