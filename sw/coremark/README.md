# CoreMark 构建与性能统计

在本目录加载项目工具链后构建，例如：

```powershell
make DDR=1 ITERATIONS=2000 PROFILE=0 BUILD=F:/ARGONAUTICA_work/firmware/coremark_baseline
make DDR=1 ITERATIONS=2000 PROFILE=1 BUILD=F:/ARGONAUTICA_work/firmware/coremark_profile
```

`PROFILE` 默认为 0，保持原有计时和输出。`PROFILE=1` 是诊断固件，算法与 CRC
不变，在计时函数边界启停现有 MMIO 性能/缓存计数器，并在结果输出后打印
`COREMARK_PROFILE_BEGIN` 至 `COREMARK_PROFILE_END`。所有统计串口输出均在计时段之外。
两种固件布局不同，成绩分别报告，不将诊断固件的周期替代默认固件的成绩。

- `cycles`、`instr`、`branch`、`mispred`、`lduse`、`istall`、`dstall`、`traps`
  来自 `PERF_*`。`ihit`、`imiss`、`dhit`、`dmiss` 来自 `CACHE_*`。
- 启停 MMIO 操作和计时 CSR 读取有少量边界开销；统计窗口与 `Total ticks` 不完全相同。
  停止后先完成两次控制写和 64 位周期读取，再读稳定的缓存计数，包含已排队事件。
- CPI 用 `cycles/instr`，缓存命中率用 `hit/(hit+miss)`。停顿事件可以重叠，
  不能相加当作互斥的周期组成；缓存命中次数也不是退休的 load/store 指令数。
- `cycle64_delta` 用高/低/高一致性读取覆盖起止边界，可检查 32 位计时回绕。
  CoreMark 本身仍使用原来的 32 位计时：100 MHz 下单次约 42.95 秒回绕；
  2000 次 DDR 运行约 31 秒，5000 次不适合作为本端口的有效成绩。
- `PROFILE=1` 需要带性能与缓存统计 MMIO 的 DDR SoC；当前 S24 完整 ILA 位流已包含。
  不需要因软件统计功能重新综合 FPGA。该配置的 ILA 探针仍是 DDR 握手，
  运行中流水线波形采集需要另建匹配探针和位流。

每轮先开串口，再下载当前已通过时序/引脚检查的 DDR 位流，上传对应 `.bin`。
至少核对全部 CRC、2000 次迭代、无异常、测量区间不少于 10 秒和匹配的文件哈希。
主频未独立测量时，时间和 CoreMark 应注明按标称频率换算。


`DDR=1 TCM_TEXT=1 PROFILE=0`可将执行代码搬入现有TCM，数据/栈仍在DDR；S28三轮2000次均超过10秒并通过CRC。
默认TCM_TEXT=0保留DDR代码版，时间随版本变化，以每轮实际ticks为准。
TCM组合的PROFILE=1尚未验收，I Cache窗口可能为零，不能套用旧统计汇总器的非零命中假设。
构建与回退步骤见TCM操作指南（历史资料未随本源码展示版提供）。
