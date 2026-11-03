# A55：共享生产深度5×5 post8回归

`control.c` 和 `candidate.c` 都直接编译生产 `conv5x5_block`，仅将 `YOLO_DW5_POST8` 分别置0/1，不使用A54派生候选。候选共用验证、权重和输入打包/提交；旧硬件走已有冷DDR `block_post8_raw_store`，不复制两套生产算子。新开关默认0，要求DW5X5_BLOCK、BLOCK_POST8及安全ACC32；现有依赖还要求block8/1x1/input-reuse。

正常成功后恢复raw模式；能力缺失在写前选择路径，未知/矛盾ID拒绝；忙、超时、任务后或读回错误fatal，调用者丢弃输出并重新配置，不重算前缀。原固定模型合法Q24范围保持，任意溢出参数不属于原CPU控制的合法比较域。

主机驱动复用A54独立CHW/int64/除法Q24测试数据与实际RTL，但调用的是本目录的实际生产函数。三个硬件mode为0=post8、1=raw8、2=raw4，历史驱动打印A54标签不代表用了A54候选；运行器的A55结果绑定真实源/对象。正常、ASan/UBSan、参数/错误、上传逐字trace、只读/哨兵与原尺寸均覆盖。`main.c` 则是实际RV32诊断，测试当前1/2/1存储和8种短几何，控制与候选均预热后交替三轮，包含全部函数开销；同一ELF在新旧硬件下复跑。启动镜像按每mode分开，缓存绑定源/flags/编译器/镜像，改变源码须新目录。

所有过程输出应留在新的F盘工作目录，不能覆盖历史证据或复用旧ELF。先运行普通/ASan实际RTL，再同ELF三个RV32 mode；整网还需逐层完整张量、真实生产ELF的TCM/DDR/SP/SU/CFG及有界VLA核验，通过后才实体下载。本目录脚本不直接连接开发板或PDS。

```powershell
$run = 'F:\ARGONAUTICA_work\board_tests\a55_replay_new'
$py = 'E:\Python3.13.5\python.exe'
& $py -X utf8 -B .\sw\tests\ai_dw5_post8_production\run_host.py --out $run --mode 0
& $py -X utf8 -B .\sw\tests\ai_dw5_post8_production\run_host.py --out $run --mode 0 --sanitize
& $py -X utf8 -B .\sw\tests\ai_dw5_post8_production\run_host.py --out $run --mode 1
& $py -X utf8 -B .\sw\tests\ai_dw5_post8_production\run_host.py --out $run --mode 2
& $py -X utf8 -B .\sw\tests\ai_dw5_post8_production\run_soc.py --out $run --mode 0
& $py -X utf8 -B .\sw\tests\ai_dw5_post8_production\run_soc.py --out $run --mode 1
& $py -X utf8 -B .\sw\tests\ai_dw5_post8_production\run_soc.py --out $run --mode 2
```

生产固件需从机器配置读取完整flags并显式设置YOLO_DW5_POST8，不能使用通用默认构建替代已验证固件。正式TCM/栈仍24KiB/8KiB/256B保护；诊断栈不能继承生产。历史A54生成器固定旧源，不应对现在已修改的生产头盲跑；A55测试直接用新共享实现。
