# A53：独立深度 3×3 批量行窗口原型

本目录只用于实验。正式仍为 A49 硬件＋A50 固件；本原型不在生产或 PDS 源清单中。新模块在 `rtl/experimental/ai_dw3_batch.v`，测试包装在 `sim/fixtures/ai_dw3_batch_overlay.v`。包装默认关闭，运行器临时重命名原包装的模块名，保留其余逻辑，不修改生产文件。

一次任务处理一个通道的 1～8 个内部横向输出，stride 为 1/2。条带宽度为 `3+(n-1)*stride`，最大 17；三行按行分开上传，每行最多 5 个 little-endian 字。逻辑有效输入最多 51 字节，实际固定条带存储 **60 字节**；另有 12 字节权重字、8 字节输出、9 个 16 位乘积寄存器、32 位累加与 Q24 参数及控制状态。没有外部 DMA、动态分配或一致性变更。

硬件有独立九个 signed INT8 乘法通道；直接索引条带产生 MAC，自动推进横向位置，不向旧核心内部模拟 PIX/CTRL 写入。复用最终安全版本 `ai_q24_post` 的语义，但原型有一份独立量化器，逐输出串行处理，不承诺每周期一个输出，也没有复用现有核心的物理乘法器。增加的 APM/LUT/FF 和 100 MHz 时序必须另测；不能继承 A49 的资源和时序结论。

调用者须独占 AI 外设，保持输入、权重和参数只读。软件首次校验完整形状、指针跨度及输出不重叠，然后只读探测能力；缺能力时，首次新寄存器写之前回退到原 `conv3x3_rolling`。非内部区域仍走原驻留权重算子。任务错误、超时或迟到错误立即返回，不能重算已写前缀；调用者应丢弃失败算子的输出。每批结果只有全部成功才公开，整个算子的不同批次不构成原子事务。

新寄存器均在 AI 页的 `0x3xx`，原寄存器保持原语义。新任务拥有期间，旧页请求不转发且使任务失败。软件不能在别的使用者仍操作旧核心时调用本实验。

| 偏移 | 语义 |
| --- | --- |
| 300 | 只读能力 `0x41353331`（A531） |
| 304 | 读 busy/done/error 位 0/1/2；写 1 提交，2 清全部有效位并开始新通道，4 清条带/错误并保留通道参数 |
| 308 | 输出数 bits 3:0（1～8）、stride2 bit 4、leaky bit 5；设置后须重新上传条带 |
| 30c / 310 | signed32 multiplier / bias |
| 314 / 318 | 权重字索引 0～2 / 自增数据；仅低 9 字节参与计算 |
| 31c / 320 | 条带字索引 0～14 / 自增数据；各行基址分别 0、5、10 |
| 328 / 32c | 合并结果字索引 0～1 / 自增数据；尾部无效字节归零 |
| 330 | 已公开的输出字节数，否则 0 |
| 334 / 338 / 33c | 自复位起累计的 DOT / 接受任务 / 内部成功量化项，uint32 回绕计数 |

必须先有合法形状、全部 3 个权重字、两个量化参数、每行所需的全部条带字，才能提交。提交消费条带有效位；每批/每行必须重新播种。索引越界、保留位、非整字写、未对齐、写只读位置、忙写/冲突和过早/越界结果读均使错误保持。错误状态输出数据及输出字节计数屏蔽为零，累计诊断计数仍可读；只有 idle 时的 2/4 清除命令可恢复。512 周期内部 watchdog 保护本地任务；软件最多轮询 2048 次。量化器若自身卡死保持 busy，DRAIN 不承诺恢复，须复位；软件仍有界返回，不重试。

独立 oracle 用 CHW 坐标及 int64/整数除法实现 Q24，半值远离零，leaky 常量 1677722，裁剪 [-127,127]。RTL 对舍入或加 bias 超出已定义 signed32 域的情况报错；不能将原控制路径的固定模型范围扩展为任意溢出参数支持。

复跑须另建 F 盘输出目录；以下脚本不会连接实体板或运行 PDS。不要复用冻结证据目录。`run_soc.py` 在首次构建后共用该诊断镜像，供新旧硬件对照；只要源码、flags 或工具链变化，必须另建输出目录，不能将已有 ELF 的存在当作增量构建检查。

```powershell
$run = 'F:\ARGONAUTICA_work\board_tests\a53_replay_new'
$py = 'E:\Python3.13.5\python.exe'
& $py -X utf8 -B .\sw\tests\ai_dw3_batch\generate_expected.py
& $py -X utf8 -B .\sw\tests\ai_dw3_batch\run_offline.py --out $run
& $py -X utf8 -B .\sw\tests\ai_dw3_batch\run_offline.py --out $run --sanitize
& $py -X utf8 -B .\sw\tests\ai_dw3_batch\run_protocol.py --out $run
& $py -X utf8 -B .\sw\tests\ai_dw3_batch\run_soc.py --out $run --enabled 1
& $py -X utf8 -B .\sw\tests\ai_dw3_batch\run_soc.py --out $run --enabled 0
& $py -X utf8 -B .\sw\tests\ai_dw3_batch\run_soc.py --out $run --enabled 1 --full
& $py -X utf8 -B .\sw\tests\ai_dw3_batch\audit_elf.py --out $run --variant short
& $py -X utf8 -B .\sw\tests\ai_dw3_batch\audit_elf.py --out $run --variant full
```

RV32 比较使用当前 1/2/1 存储结构、2MiB DDR 模型，保留 24KiB TCM 代码、8KiB 栈与 256B 保护。计时包住完整算子：校验、打包、权重/参数/条带上传、提交、等待、合并读回、CHW 存储及结束清理；预热一次后交替执行三轮。短测试与原尺寸测试分开编译，不跨 ELF 比较速度；新旧硬件短测试必须使用完全相同的 BIN/ELF。主机执行耗时不作为 RV32 性能，RV32 仿真周期不作为实体板或整网成绩。

本轮冻结结果与是否推进的决定见 A53 验证归档（历史资料未随本源码展示版提供）。
