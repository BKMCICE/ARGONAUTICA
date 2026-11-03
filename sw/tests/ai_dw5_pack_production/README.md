# A75 默认关闭的 DW5 固定布局打包集成

`YOLO_DW5_PACK_FAST=1` 只替换生产 `conv5x5_block` 的输入打包函数。
算法来自 A74：内部完整 5×5 窗口按 9/9/7 字节布局直接加载；边界、裁剪及非标准 helper 参数使用原打包器。
默认值为 0，要求 `YOLO_DW5X5_BLOCK=1` 和 `YOLO_DW5_POST8=1`。
post8 和旧 raw8/raw4 使用同一个生产实现；任务失败时上层必须丢弃部分输出。

```powershell
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_dw5_pack_production/run_host.py --out F:/ARGONAUTICA_work/board_tests/a75_recheck/rtl --mode 0
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_dw5_pack_production/run_host.py --out F:/ARGONAUTICA_work/board_tests/a75_recheck/rtl --mode 0 --sanitize
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_dw5_pack_production/run_host.py --out F:/ARGONAUTICA_work/board_tests/a75_recheck/rtl --mode 1
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_dw5_pack_production/run_host.py --out F:/ARGONAUTICA_work/board_tests/a75_recheck/rtl --mode 2
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_dw5_pack_production/run_graph.py --out F:/ARGONAUTICA_work/board_tests/a75_recheck/graph
```

`control.c`、`candidate.c` 分别以开关 0、1 编译实际生产函数。重用 A74 的独立 CHW/int64/Q24 oracle 和实际 RTL 测试驱动；输出中的 `A74` 是重用驱动的标记，A75 结果 JSON 绑定本轮两组编译对象和源文件。
四种模式覆盖 256 个完整算子案例、40,950 个直接打包案例、尾部/边界/负值及任务中途错误。

整网测试的 control、candidate 均开启现正式 identity forwarding，仅新 DW5 开关不同。六组输入、六种模式逐字节比较全部 131 层输出，并检查检测输出和 MMIO 统计；域扫描与故障注入只在 host observer 中执行。
这些测试不代表 RV32 性能或实板验收。生产 TCM/栈必须绑定新 ELF 单独检查，性能必须以相同实板整网测量为准。
