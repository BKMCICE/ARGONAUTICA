# A35 cache统计计数器分段实验

本轮最终状态见A35冻结记录（历史资料未随本源码展示版提供）：逻辑/CPU/cache/DDR对照PASS，PDS原始约束独立TA完成但setup/slow hold/fast hold为−0.209/−0.196/−0.195ns，候选未下载、未采用。正式A02＋A25不变，原正式串口恢复通过，用户本轮已确认绿条82正常，显示跟进（历史资料未随本源码展示版提供）。以下为原型接口及复现说明。

`cache_stats.SPLIT_COUNTERS=1`将四个32位计数器各拆为四个8位段，各段用更新前低位的归约与独立判断进位，试图缩短A34报告中的清零到计数器CE级联。默认0保留原计数表达式；没有寄存clear或更改ready、事件延迟、清零优先级、enable采样时刻及模2^32溢出。

DDR顶层参数`CACHE_STATS_SPLIT_COUNTERS`和PDS环境变量`RV32_CACHE_STATS_SPLIT`默认0；本轮只测试分段开关及固定的A34 150ps局部物理配方，不调整100MHz、种子或全局hold目标。正式A02/A25发布文件和配置JSON保持不变。

`sim/tb/tb_cache_stats_equivalence.v`由独立标量计分板同时检查冻结的A34参考、默认和分段实现，含事件mask/四种控制、连续写、随机地址/byte-enable/复位、8/16/24位进位及32位回绕。参考文件由验证脚本从固定Git提交提取，不能用候选自身充作参考。溢出使用无持续force的验证初值注入，后续更新由RTL执行。

本目录C程序运行在真实RV32/cache/DDR RTL模型，检查MMIO使能/清零、已接受事件排空、禁用时DDR流量不计数、地址别名、原byte-enable策略和连续写。生成物须用`BUILD=F:/ARGONAUTICA_work/...`集中放置。

以上是实验接口说明，存在源码不表示PDS或实体板通过；最终状态以对应冻结validation记录为准。只有原始全部时序和113引脚通过后才下载候选，不直接把新8输出硬件接入整网。
