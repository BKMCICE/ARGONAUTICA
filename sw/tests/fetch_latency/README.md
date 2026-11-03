# 取指路径对照实验

仅用于 DDR SoC 的诊断程序：将同一份 140 字节位置无关指令复制到片上 RAM
`0x00008000` 和 DDR `0x80008000`，执行 FENCE.I 并逐字核对。
两处各先预热，再交替测量三轮；每轮 20000 次循环，循环每次为 32 条 NOP、
一条 ADDI 和一条 BNE，末尾一条 RET。两处执行相同的 680001 条循环/返回指令，
没有数据访存。串口打印在统计停止后进行，窗口还包含少量调用和启停开销。

加载项目工具链后，在本目录运行：

```powershell
make BUILD=F:/ARGONAUTICA_work/firmware/fetch_latency
```

默认 `FETCH_ITERATIONS=20000`；RTL 冒烟可用 `FETCH_ITERATIONS=8 BAUD=3125000`
缩短循环和模拟串口等待，必须与板上默认次数的测量分别报告。

先启动 UART 上传工具，再重新下载当前通过的 S24 DDR ILA 位流并上传 `.bin`。
应收到六条 `FETCH_SAMPLE` 和 `FETCH_LATENCY_PASS`，不能有异常。
本程序保留并覆盖上述两块临时区域，只能独立运行，不与其他应用并行。

比较 `cycles/instr`、`istall`、`imiss`：若 DDR 路径命中率高却明显更慢，
可支持优先排查缓存命中响应与取指适配握手的方向。这是包含分支和调用边界的
路径吞吐对照，不能等同于单次 DDR 物理访问延迟，也不能外推优化后的 CoreMark 分数。
