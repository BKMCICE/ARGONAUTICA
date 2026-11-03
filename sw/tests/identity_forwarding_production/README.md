# A71：默认关闭的固定模型identity转发

`YOLO_IDENTITY_FORWARD=0`保留原布局和运算，显式1时需要`YOLO_REUSE_ACTIVATIONS=1`及`YOLO_1X1_ACC32=1`。Make在链接之前强制运行`tools/yolo_check_identity_forward.py --check`，绑定完整图、相关C/头/量化RTL源码和别名生命期。生成头单独为`model_identity_arena.h`；原`model_arena.h`不变。`--write`是审核后的显式更新命令，普通构建不会自动接受改变的合同。

20个dropout/head只有在成功的前一卷积输出已饱和至[-127,127]时才可转发。原`passthrough_layer`仍保留全部256种INT8的裁剪语义（-128→-127），不是任意INT8均可省运算。目标端不逐字节扫描域；正确性依赖审核后的生产者、成功错误传播、匹配量化硬件及固定图。合同检查不是对任意C/RTL/故障的形式化定理；绕过Make的直接编译不替代强制检查。

`run_host.py`编译实际生产main，开关0为控制、开关1使用新头；没有生成或改写main副本。六图×控制/转发/旧raw8/旧raw4/缺ID/ASan，共36次，比较每层131个完整输出、双头与完整检测。主机observer在每次转发时检查别名地址、倍率和全部输入字节，注入-128必须由observer退出98；这不是声称目标固件能检测任意损坏的值域。主机MMIO模型与ASan结果不能替代实板或时序。

```powershell
python -X utf8 -B tools/yolo_check_identity_forward.py --root . --check
python -X utf8 -B tools/tests/test_yolo_identity_contract.py
python -X utf8 -B sw/tests/identity_forwarding_production/run_host.py --out F:/ARGONAUTICA_work/board_tests/a71_fresh
```

复跑用新F盘目录。新ELF必须重新证明TCM、DDR对象和栈；关闭开关逐字复现正式BIN，通过实板三轮与恢复后才报告新速度，之后多图/新显示完成才采用。无硬件RTL变更或新PDS/CoreMark/AP结论。
