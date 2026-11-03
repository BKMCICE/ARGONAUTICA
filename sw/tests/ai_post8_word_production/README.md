# A80 production post8 word-store integration checks

The actual `sw/yolo_fixed/main.c` is compiled separately with the default-off
`YOLO_POST8_WORD_STORE=0/1`; the A79 actual-RTL fixture compares control,
namespace placebo and candidate against an independent CHW/int64/division-Q24
oracle. Host-only cache counters have distinct namespaces. Three capability
modes plus post8 ASan/UBSan cover aligned/unaligned/tails, sentinels, readonly
inputs, exact MMIO traces/counts, error/partial-output/no-retry boundaries.
There is no host timing or code-layout performance claim.

`run_graph.py --out F:/...` runs six inputs across six configurations, compares
all 131 tensors, original stdout/detections and 20 forwarded-input domains,
and rejects an injected -128 domain violation. This uses a mathematical MMIO
model; the native peripheral suite above uses the actual unchanged RTL.

Target checks must rebuild the exact ELF: flag0 reproduces A75, flag1 reuses
the existing cold DDR section for post-forward detection reporting because
its initial hot-only image exceeded 24 KiB by 20 B. No hot operator/stack is
moved or budget expanded. Real long calls, every SP/CFG/frame, guarded legacy
VLA, static DDR objects and three negative audits are required before board
runs. That placement changes postprocess latency; forward cycles do not
include it. Do not infer end-to-end speed or adoption from this suite.
