# A92 offline production leaky integration

Default-off YOLO_DW3_LEAKY_CLIP modifies only dw3_quant's final leaky+clip.
Original first Q24/bias, rolling window, legacy dot protocol remain unchanged.
run_rtl.py uses A91's independent scalar/CHW oracle and actual RTL fixture,
but each of the three C translation units includes the actual production main:
flag0 control/placebo and flag1 candidate. A91 log labels identify the reused
fixture, not an old result. Run A61 normal, A61 ASan/UBSan and oldest legacy.

run_graph.py runs actual production main with flag0/flag1, six source images,
all 131 tensor bytes, old accelerator capabilities, missing accelerator and
ASan/UBSan. Host MMIO here is mathematical; separate operator tests drive RTL.
The existing forwarded-input observer rejects a -128 injection; no new
runtime scan is added to firmware. Host timing is not RV32/board timing.

Board is cooling: no download, serial or JTAG access is part of these scripts.
Physical dog timing, old bitstreams, scenes and fresh display are NOT_RUN.
Formal A61+A83 and its current_board_configuration.json remain unchanged.
