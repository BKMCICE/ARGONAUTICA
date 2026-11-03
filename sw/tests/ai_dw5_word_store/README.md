# A88: DW5 post8 safe packed-word writeback, isolated experiment

`generate.py` pins the current production `dw5x5_block.h` and derives a
namespace-only placebo and a candidate. The sole candidate body change replaces
the packed-result byte loop with existing `post8_word_store` plus `px += count`.
Production `sw/yolo_fixed`, RTL, PDS and the formal configuration are unchanged.
All three use the accepted fixed DW5 packer and the exact same MMIO protocol.

The helper uses alias-safe builtin memcpy only for four aligned valid bytes on
little endian targets. Unaligned addresses and counts 1..3 use byte stores.
The candidate also hoists output address calculation per packed word; any speed
result includes that compiler effect and must not be attributed to SW alone.
No restrict or uint32_t destination cast is introduced. The descriptor, inputs,
weights and parameters must remain stable for the complete call; output must not
overwrite descriptor metadata. Existing validated tensor non-overlap checks and
fatal-error/discard-whole-layer semantics are unchanged.

`run_host.py --out F:/... --mode 0|1|2 [--sanitize]` drives unchanged actual
accelerator RTL for post8 / raw8 / raw4 capability modes. It checks 300 complete
operators, independent int64 CHW/Q24 output, all MMIO writes, offsets 0..3, real
20x20x120 and 10x10x96 shapes, partial rows, tail counts, signed extrema, readonly
inputs, capability/shape/overlap guards and first/second-task fatal failures.
Direct store probes check 48 count/alignment/value combinations with sentinels.
Host time is not target latency. Address/undefined sanitizers complement guards.

Build from the project toolchain environment:

```
make -B -C sw/tests/ai_dw5_word_store A88_FULL=1 BUILD=F:/.../full
python -B sw/tests/ai_dw5_word_store/audit_elf.py --out F:/... --variant full
```

`A88_FULL=1` measures both real DW5 sizes; `0` covers eight smaller edge shapes.
For each shape and destination offset 0..3 there are three warmups then all six
orders of control/placebo/candidate. Every call validates an independent expected
FNV, output sentinels, raw-mode reset and final input/weight/parameter hashes.
ICF and jump tables are disabled in this diagnostic; inspect exact ELF words,
namespace-control identity, complete SP writers/direct call graph and frame sum
before download. This is a complete-operator experiment, not whole YOLO evidence.
The separate temporary full-image size trial is not an execution qualification.

Keep outputs under `F:/ARGONAUTICA_work/board_tests/20261025_a88_dw5_word_store`.
After board measurements restore the hash-bound formal A61+A83, run real dog,
check detections and stack guard, and obtain a fresh HDMI observation.
