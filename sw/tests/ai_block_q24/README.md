# A20 block Q24 reuse candidate

**A26当前正式为A02＋A25 RGB分块版，保留A21的块1×1量化/写回复用。** dog三轮平均10.02031677秒，直接回退A21。当前证据（历史资料未随本源码展示版提供）。以下A20/A21/A22内容保留为历史测试记录。

**A22多图实板及新显示确认通过，A02＋A21已正式采用，三轮dog平均11.35170091秒。** 原A16保留为直接回退。A22实际证据（历史资料未随本源码展示版提供）。目标程序不包含whole_graph.c；它仍只用于主机完整张量观察。以下A20/A21记录按当轮范围保留。

A21整网验证完成：候选三轮真实dog平均11.35170091秒，较A16耗时减少6.84%，正式尚未替换。完整证据与A22入口（历史资料未随本源码展示版提供）。新增whole_graph.c为仅主机观察器：直接包含生产main.c，在HOST_LAYER点保存131层完整CHW输出；六图24次flag0/flag1/旧ID回退/消毒候选逐字节一致。run_host.py见证据repro目录；目标构建不包含观察器。

A20三轮实板对照及原A16恢复、新显示确认均通过。20×20/120→255与40×40/16→96完整算子分别耗时减少6.32%/18.06%；1×1空间224→7小任务耗时增加2.17%。完整证据和A21开工点（历史资料未随本源码展示版提供）。尚未测量候选整网，正式不变。

`make -C sw/tests/ai_block_q24 BUILD=<F:-work-directory>` builds a diagnostic,
not a whole-model firmware. `control.c` and `candidate.c` include the actual
production operator with `YOLO_BLOCK_Q24_REUSE=0/1`, all profiling disabled.
Each TU has its own 300 KiB diagnostic cache. Production keeps one cache.

The new flag defaults to 0 and requires block1. Candidate output must be
disjoint from input, weights, parameters and layer descriptor. Rejections
occur before MMIO. Q24 rounding, negative leaky and clipping use the existing
production helpers. Scalar tests use division and independent CHW indexing.

Tests include 10,080 Q24 tiles (sign, half-step rounding, bias, saturation,
leaky on/off, 1..8 pixels), four alias guards, eight full operator shapes with
input/output tails, grouped stride2, cache/no-cache and both A18/A19 hotspots.
Host adds two data patterns, 144 small shapes and six transport failures.
Target uses independent Python-generated full-output hashes and bytewise
control/candidate comparison, read-only object hashes and full sentinels.

After warmup, target alternates order for four complete-operator pairs per
shape. `A20_SHORT=1` uses only the two small shapes and one measured pair each
for RTL, with the same Q24/alias tests but a different ELF. Timing differences
include code/cache layout and validation overhead; they are not whole-model
speedups. Adoption requires separate whole-model and multi-image validation.
