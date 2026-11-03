# A50 shared production post8 verification

`control.c` and `candidate.c` include the actual production `main.c` in
separate translation units, with `YOLO_BLOCK_POST8=0/1`. They share no copied
operator body. Their cache scratch objects are distinct and both are checked.
The independent division-based CHW oracle and frozen expected hashes reuse
the A48 diagnostic inputs. Historical A48 sources remain unchanged.

The host harness checks 266 geometries, 38 rejection guards, six original
transport faults, two inconsistent capability IDs, missing channel parameters
and unsafe Q24 model parameters. Ordinary and ASan/UBSan executions check exact
weight/input/task/packed counts, read-only inputs, output sentinels and old
four/eight-output fallback. `whole_graph.c` observes all 131 actual production
layer tensors before arena reuse. The strict host transport is not RTL proof.

The target Makefile builds a short diagnostic with two real production
functions. Its 11 geometries retain channel dimensions but shrink five large
spatial dimensions. Run the same ELF with
`sim/tb/tb_ai_block8_post_production_soc.v` on post8, raw8 and raw4 hardware;
check accepted MMIO and internal engine counters, guard and complete output.
This diagnostic is not the production YOLO image or a board latency score.

Production builds use the original formal flags plus `YOLO_BLOCK_POST8=1`.
The new flag defaults to zero and requires block8/block1/safe int32 mode.
Capability `0x28=A331` alone enables raw8 only; `0x2c=A481` additionally enables
post8. Old hardware falls back before writes. Busy/errors/timeouts never retry
after partial results. Success restores raw mode. Only the new build places
the raw fallback helper in the existing `.ddr_rgb3` cold DDR code region;
the original hot TCM, 8 KiB stack and 256-byte guard limits remain unchanged.

Generated outputs belong in a new F:/ARGONAUTICA_work directory. Physical
timing qualification is by the exact A49 bitstream; model equality, actual ELF
capacity/stack proof, physical-board latency and adoption are separate gates.
