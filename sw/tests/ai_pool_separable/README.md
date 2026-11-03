# A93 isolated separable maximum-pool experiment

The actual fixed graph contains 10x10x48 pools at layers109/111/113,
kernels3/5/9, stride1, pad1/2/4, Q24=29567173. This proposal computes
horizontal maxima to one caller-owned100B channel scratch, then vertical
maxima, then the unchanged original Q24/clip. The initial -127 is preserved
at both passes, including raw-128 tests. Requantizing between passes is wrong.

No production dispatch includes prototype.h. Unsupported shapes are rejected
before writes. The caller must provide nonoverlapping stable tensors and
scratch; this prototype does not validate arbitrary spans or partial aliases.
It is not ready for board programming or production adoption.

test.c includes the actual production maxpool_layer, compares all full
outputs to the proposal and an independent 2D/int64/division oracle, with
256 constant inputs, structured extremes, random cases, offsets0..3,
sentinels, readonly inputs, and18 rejection cases. Run normal and ASan/UBSan.
Host elapsed time and fewer sample comparisons do not imply RV32 speed.

Pending: isolated target whole-operator three-way timings and actual target
ELF/stack/scratch proofs, then separate whole-model integration/qualification.
Use existing A92 as the only full-model board candidate until measured.
