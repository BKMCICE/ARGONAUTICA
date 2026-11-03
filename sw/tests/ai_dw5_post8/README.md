# A54：现有 post8 的深度 5×5 软件实验

这是独立诊断，不修改生产 RTL、PDS、固件或机器配置。正式仍为 A49＋A50。新算子由 `generate.py` 从固定生产 `dw5x5_block.h` 派生；脚本核对归一化源 SHA、权重上传循环和完整输入打包/提交文本。控制直接调用实际生产 `conv5x5_block`，没有另写控制算法。

保留原验证、分组/CHW、通道权重驻留、三块 9/9/7、每批最多 8 像素及原 `dw5_pack5`。只改能力探测、post8 模式、每通道 Q24 参数和合并 INT8 结果读回。先读取基础 A011、raw8 A331 和 post8 A481；基础缺失返回 UNSUPPORTED，未知或矛盾能力返回 HW_ERROR。post8 缺失时在任何写之前调用原控制路径；开始任务后错误绝不回退或重算前缀。成功退出写 0x204=0 恢复 raw 模式，失败则返回且由调用者丢弃全部输出、复位/重新配置外设，不能继续使用不确定状态。

现有硬件支持 pixels1～8 / outputs1 / blocks3 / last7；参数索引固定为 0，每通道装一次 multiplier/bias，所有空间批次复用。原核心形状/输入/权重上传逐字与控制相同，dot 数仍为每输出 3 次。启用 post 时，合并读回每批 `ceil(pixels/4)` 字；无改动 DMA 或缓存一致性。硬件算术范围沿用安全 scalar Q24：半值远离零、加 bias 检查 signed32、leaky 1677722、裁剪 [-127,127]。任意不合法溢出参数不属于原控制软件的可比较输入域。

调用者须独占整个 AI 外设，输入、权重及参数只读，缓冲区跨度合法，输出与它们不重叠。形状、cap、忙状态拒绝发生在写之前。正常/ASan 驱动实际生产 RTL，分别比较原控制、候选和独立 CHW/int64/除法 Q24，并核对完整上传 trace、哨兵、所有读取/提交计数及成功 raw 模式恢复。注入超时/任务后错误/迟错误不得部分重试；参数丢失和加偏置溢出由真实 RTL 拒绝，忙写结果无效及复位状态也有检查。

RV32 使用当前 ICACHE_DRM1/DCACHE_TAG_STORAGE2/REGFILE_STORAGE1、2MiB DDR 模型、24KiB TCM 代码、8KiB 栈和 256B 保护。每个硬件模式有独立启动镜像目录。同一短 BIN/ELF 对照 post8/raw8/raw4；完整测试是原尺寸 20×20×120 和 10×10×96，均 stride1/pad2/leaky1，对应层125/127与116/118。所有数据为可复现合成值，不是整网激活或 AP 数据集。计时包含完整函数、参数/模式切换、原打包和全部 wait/readback/store；预热后交替三轮。新实际 ELF 重新审核栈/内存，不能继承先前 912B 或正式 6512B。

输出必须使用新的 F 盘目录；不要覆盖冻结证据。构建缓存用 C/头/链接脚本/flags/编译器及 ELF/BIN SHA 绑定，源码改变时拒绝旧镜像；工具链变更也应另建目录。主机 native/Verilator 构建和 WSL TMPDIR 均放 F 盘。

```powershell
$py = 'E:\Python3.13.5\python.exe'
$run = 'F:\ARGONAUTICA_work\board_tests\a54_replay_new'
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\generate.py --check
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\generate_expected.py
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\prepare_fixture.py --check
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\run_host.py --out $run --mode 0
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\run_host.py --out $run --mode 0 --sanitize
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\run_host.py --out $run --mode 1
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\run_host.py --out $run --mode 2
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\run_soc.py --out $run --mode 0
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\run_soc.py --out $run --mode 1
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\run_soc.py --out $run --mode 2
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\run_soc.py --out $run --mode 0 --full
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\audit_elf.py --out $run --variant short
& $py -X utf8 -B .\sw\tests\ai_dw5_post8\audit_elf.py --out $run --variant full
```

这些命令不运行 PDS、不连接实体板。主机耗时不当作 RV32 周期，仿真周期不当作实板或整网提速。本轮结果与下一步见 A54归档（历史资料未随本源码展示版提供）。任何整网集成都须共用上传/验证路径并复用现有冷 DDR raw-store，不能将本实验的两套函数一起塞入只剩 416B 的正式 TCM。
