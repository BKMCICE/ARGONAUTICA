# A24 ordinary RGB 3x3 block prototype

**A26五图实板及新显示确认通过，A02＋A25已正式采用，三轮dog平均10.02031677秒。** 原A21为直接回退。完整证据（历史资料未随本源码展示版提供）。生产实现在sw/yolo_fixed/rgb3_block.h；RGB3_PRODUCTION=1选用production_operator.c复用独立算子测试，并执行生产热路径及DDR冷回退；dispatch.c仅主机核验错误传播及部分输出后不回退。以下A24原型记录按当轮范围保留。

Diagnostic only. Production dispatcher and formal A21 are unchanged.
`main.c` includes the actual production `conv3x3_input3_prepacked` as control.
`rgb3_block.h` uses the existing A02 block engine: three nine-lane input
vectors, four output channels and up to eight pixels per task. Weights remain
resident through the spatial scan. No RTL, PDS or model changes.

The prototype accepts groups1/ic3/size3, stride1/2, pad0..2 and valid cropped
output dimensions. Shape/range/alias rejection happens before MMIO; missing
ID, busy, timeout, hardware error and bad result status propagate. Raw27 INT8
products fit int32; production int64 Q24/rounding/leaky/saturation are reused.

Host tests compare full outputs against an independent spatial CHW/division
oracle, production control and independent Python reference hashes, ordinary
and ASan/UBSan. Cases cover borders, narrow images, stride, crop, input signs,
output channel/pixel tails, readonly objects, full sentinels and transport
errors. Target compares complete outputs and frozen independent hashes.

Physical timing alternates warmed complete operators, including candidate
validation/packing/transport/quantization. Seven shapes include the real stem
320x320x3 -> 160x160x8. `A24_SHORT=1` tests the other six small shapes with a
different ELF for actual RV32/DDR/legacy+block RTL, not full stem simulation.
Local operator gains do not establish whole-model speed or adoption.
