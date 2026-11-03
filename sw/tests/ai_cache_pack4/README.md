# A82 four-pixel input-cache transposition

Isolated complete 1x1 control/placebo/candidate. The candidate only changes
one call to the cache builder. Canonical stride1/full dimensions, plane divisible
by4 and aligned input enable alias-safe constant memcpy word loads and 4x4 byte
transposes; missing channels are zero, all other geometry/alignment uses the
original builder. Same 300KiB cache layout and MMIO sequence. No producer/RTL,
quantization, graph, model or identity-contract changes; formal is A61+A80.

Native actual peripheral RTL compares three complete operators and independent
CHW/int64/division Q24, MMIO traces/counts, errors/readonly/sentinels. Separate
1312 direct cache cases compare every cached word/unused footprint, alignment,
stride/crop fallback and an independent packing oracle, with fastpath counters.
Target uses all three distinct operators, no IPA identical-code folding, full
operation interval and six orders per shape; not merely cache-build timing.

The prototype's all-TCM layout does not prove production fit or whole-network
speed. Stride2 and uncached target shapes are negative controls. Physical inputs
are aligned; unaligned input fallback is covered natively and by exact ELF
alignment/word-load proof. Only physical output FNV and sentinels are checked;
native output/cache comparisons are full byte/word equality. No AP/video claim.
