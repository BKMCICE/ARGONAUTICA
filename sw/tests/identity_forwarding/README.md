# A70：identity张量转发的隔离主机原型

生产`main.c`、`model_arena.h`、Makefile和当前机器配置保持不变。`tools/yolo_plan_identity_arena.py`提出一份独立布局，只合并倍率1、形状一致、紧邻卷积输出的dropout/head。固定模型20层可转发，逻辑复制字节522700B；激活arena从870400B降为819200B，差51200B。不是物理DDR事务/带宽或板上速度测量。

规划先把所有消费者（含route/shortcut）映射到存储根，再取整个别名组最后一次读取，head保持至最终哈希/后处理。非identity算子的输入/输出生命期仍包含同一消费时刻，不允许原地覆盖。独立32B块所有权模拟检查每个读者和全部仍存活值，不能把旧偏移简单改成前一层偏移。

转发只在成功算子饱和值域[-127,127]成立时等价；任意INT8的-128仍需clip成-127。本原型在每次转发前扫描输入域，并额外注入-128验证拒绝。源级值域合同审核及固定图测试不是任意C/RTL/故障模型上的形式化定理。

```powershell
python -X utf8 -B -m unittest discover -s tools/tests -p test_yolo_identity_arena.py -v
python -X utf8 -u -B sw/tests/identity_forwarding/run_host.py --out F:/ARGONAUTICA_work/board_tests/a70_new_run
```

输出必须放新F盘批次，避免覆盖封存文件。主机运行在新目录生成替代arena头、只修改identity分发的C副本和原有完整张量观察器副本；原生产函数及层序保持。六图×正式控制/转发/旧raw8/旧raw4/缺ID/ASan，共36次，每次131个完整张量和原参考stdout相等。控制与转发使用同一数学加速器模型，不是新RTL或实板结果；native墙钟时间不用于性能结论。

后续若生产接入，需默认关闭开关、模型/布局证书绑定、控制BIN逐字复现、新实际ELF栈/TCM/DDR、完整张量及板测。不能用本原型估算目标端代码大小/栈或自动更换当前正式固件。
