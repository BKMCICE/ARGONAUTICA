# A68：倍率为1的passthrough快速路径

生产`YOLO_IDENTITY_FASTPATH`默认0，显式1时，仅在dropout/head的`prev_q24==16777216`使用逐字节`clip8(input[i])`，其他倍率保留原Q24路径。对于全部256种INT8编码精确相等，包括-128必须映射为-127；不直接memcpy，不改变激活规划、输出缓冲或模型。当前固定模型18个dropout和2个head都满足该倍率，未将route/maxpool/upsample纳入本改动。

`run_native.py`从当前生产`main.c`逐字提取apply_q24/clip8/passthrough函数，分别编译开关0/1，与独立int64除法oracle对照。普通和ASan/UBSan各116用例，覆盖20个模型完整形状、12个含极值/半值的倍率与8种短尾、全部256输入编码、精确原位、只读输入、输出哨兵及零长度空指针。实际计数写入`native_summary.json`；native时间不用于板端性能。

```powershell
python -X utf8 -B sw/tests/identity_passthrough/run_native.py --out F:/ARGONAUTICA_work/board_tests/a68_new_run
```

本机借用已有Ubuntu-24.04/GCC，生成源码、构建、日志及TMPDIR均集中F盘。必须使用新输出批次，避免覆盖冻结文件。完整生产接入还需关闭开关逐字复现正式BIN、全131层数值对照、新实际ELF栈/TCM/DDR及实板计时，不能从此局部语义检查推断整网提速。CPU/外设RTL不因该软件开关改变。
