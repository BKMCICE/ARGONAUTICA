# A91: original rolling/dot operator, only bounded leaky plus final clip

The accepted first Q24 and bias, three-segment rolling loops, border packing,
resident weights and per-pixel PIX/START/DONE/ACCUM are unchanged. The candidate
changes only the second leaky Q24 plus final clip: v<=-1265 saturates to-127;
negative v above that threshold uses unsigned32 magnitude*1677722 plus half,
shift24 and negation. Nonnegative/nonleaky uses the original clip. INT_MIN is
handled before negation. A compile guard requires the fixed leaky multiplier.
No LUT, new tensor cache, task batching, timeout contract, RTL or PDS change.

`generate.py --check` pins the production header and proves namespace-only
placebo plus one candidate quant body change. `leaky_clip.h` is separate from
the accepted header. This is not A30's rewrite of the general/first Q24 round.
The full-int32 activation-composition proof uses monotonicity above1265 and
exhaustive magnitudes0..1264; largest product+half is2129029216<2^31. It does not
extend the accepted first-Q24/bias valid arithmetic domain.

`scalar_tests.h` independently computes int64/division round-away reference.
26410 grouped cases cover dense[-4096,4096], extreme int32,1264/1265 thresholds,
large leaky half-ties,4096 deterministic full-range samples and nonzero
acc/mult/bias combinations including first-Q24 exact positive/negative halves.
The four scalar bridges compare both activation-only and complete quantization.
Run these on the native sanitizer build and actual RV32 before operator timing.

`run_rtl.py --out F:/... [--legacy] [--sanitize]` drives unchanged actual RTL
through fixture-only legacy hooks;327 complete CHW shapes/offset/stride/padding
and28 guards compare original/placebo/candidate complete outputs, independent
int64 oracle, all writes/reads/weights/pixels, counts, readonly and sentinels.
No new word-prefetch path is introduced. Legacy's original unbounded DONE
contract is retained. Host time is not RV32 or board latency.

The RV32 diagnostic reuses eight accepted geometries, four DDR buffers, three
warmups and all six orders, validating whole-output oracle/equality/readonly,
scalar cases,29 guards and fresh stack guard. Exact ELF/SP/CFG/frame/negative
and multiply-codegen checks are required. A temporary full-image link trial
proves only layout/model bytes and control BIN identity; it is not a production
stack/graph/scene or performance qualification. Formal remains A61+A83.

All outputs under
`F:/ARGONAUTICA_work/board_tests/20261025_a91_dw3_leaky_clip`.
Restore the bound formal BIT/BIN and real dog after measurements, then obtain a
fresh user HDMI observation. No Flash programming; HDMI IN remains separate.
