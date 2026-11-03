# A86 isolated DW3 aligned-word rolling-window experiment

Production `sw/yolo_fixed` and RTL are unchanged. `generate.py` makes an exact
namespace/include-only placebo and a candidate that inserts one stride1 loop.
No Q24, leaky/clip, weight residency or legacy PIX/START/DONE/ACCUM change.

The original 24-bit three-row windows are retained. With all three row pointers
aligned4, at least four interior outputs remaining, and at least eight bytes
remaining in each row, read columns4..7 as one aligned word plus column3 as a
byte. Construct pending columns3..6, emit four outputs through the original
dot and quantizer, and advance each window one byte per output. Pointer/row
width checks precede loads. The fourth fetched byte is discarded and still
must remain in-row. Stride2, borders, short/unaligned rows and remaining tails
retain the scalar code. No new tensor cache, VLA, DMA, or hardware feature.

`transport.h` is native-test-only: it preserves production packing/resident
weight helpers, redirects their host dot calls to unchanged actual peripheral
RTL and uploads weights once per channel. It adds no target instrumentation.
`test_rtl.cpp` compares all output bytes, independent CHW/int64/division-Q24,
source read-only bytes, destination sentinels, full MMIO write/read sequences,
and exact per-pixel task counts. Each native word-load probe checks alignment,
one-row containment and exact input allocation span; its count matches the
expected fast-path batches. Includes -128, negative multipliers, cropped
geometry, stride2, row widths1..37, offsets0..3 and full real shapes.

The legacy primitive has an inherited unbounded DONE polling loop and no
transaction error-return protocol; this experiment does not add watchdog,
capability retries, or batch failure semantics. The fixture bounds DONE waits
to detect RTL hangs. Invalid spans/aliases/shapes must return before MMIO.

`main.c` measures complete control/placebo/candidate operators, not only
prefetch. Eight shapes, each variant warmed up, all six execution orders per
configuration, three independent configurations expected. Includes real
80x80x32,160x160x8,40x40x48 and unaligned/stride2/short/border controls. Full
output buffers and sentinels match, and FNV is checked against independently
generated NumPy CHW/int64/Q24 references. Physical checks are not board
byte-by-byte oracle reads or whole-model inference.

Ordinary O2 and stack-usage O2 BINs must be identical; audit the exact isolated
ELF's all words/SP/CFG/calls, static DDR objects and coherent negative tests
before download. This isolated ELF is not the production TCM budget. Do not
adopt without stable whole-operator gains and separate production qualification.

All generated process files belong under F:/ARGONAUTICA_work/board_tests.
Use `generate.py --check` and `generate_expected.py --check` to verify headers.
`run_rtl.py --out <F-directory>` tests the A61 composition; add `--legacy` or
`--sanitize` for other gates. Full source/artifact hashes and physical evidence
will be frozen in the validation archive after the current formal image is
restored and freshly observed. Host elapsed time is not RV32/board timing.
