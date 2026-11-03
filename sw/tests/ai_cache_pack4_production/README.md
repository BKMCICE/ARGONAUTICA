# A83 production cache-pack4 checks

Compile actual production main/header in three independent translation units:
control/placebo CACHE_PACK4=0, candidate1; POST8_WORD_STORE=1 and other relevant
1x1 flags held equal. The unchanged A82 actual-RTL fixture compares complete
output and exact MMIO trace/counts and independent CHW/Q24. Each TU owns its
own host cache/counters; direct cache bridge in the candidate TU compares the
unchanged scalar builder and production fast builder in that same storage.
Four modes: post8 normal/ASan-UBSan, raw8 and raw4. Per mode164 operators,
160 post stores and1312 cache cases cover alignment/tails/readonly/sentinels,
actual fast dispatch and error/no retry after partial progress.

run_graph.py explicitly binds the new production helper and runs six frames
across six modes, all131 tensors, stdout/detections and forwarded-input domain,
including ASan/UBSan, old capabilities/missing accelerator and injected -128
rejection by the host observer. Target has no new domain scan.

Exact new production ELF/ordinary-SU identity, closed SP/CFG/call/VLA/IRQ,
DDR objects and negative audits are required before board. Formal A61+A80
is retained until this candidate passes independent whole-YOLO three-run,
legacy hardware, exact same-BIN multi-image and fresh display qualification.
No performance conclusion comes from native time or isolated A82 percentages.
