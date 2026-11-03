# 真实SoC取指域切换检查

这是RTL仿真程序，运行于`soc_top_ddr`加原生DDR协议模型，不是供开发板直接下载的应用。测试台将ELF的TCM与DDR段分别预装到模型存储器；不经过生产UART启动器。所有跳转、失效和代码修改都由CPU执行，没有强制修改核心、Cache或预测器状态。

程序包含32次TCM/DDR往返、训练后跨域预测失败、旧DDR回填期间重定向及请求替换，并在DDR执行一段代码、通过D Cache修改其指令、执行FENCE.I后核对新指令。结束前验证结果签名，写TCM 0xf000作为tohost；非1表示失败。

固定链接位置是测试条件的一部分：TCM主入口0、训练代码1000/1080、间接跳转1120、正确目标2000；DDR算术/自修改/旧预测目标/替代函数分别为80000000/80001000/80002000/80003000。测试台检查实际覆盖，不能只凭程序源码宣称触发了竞态。

核心检查入口为`sim/tb/tb_soc_fetch_boundary.v`，参数`EARLY_READ=0/1`、`ENABLE_BTB=0/1`、`READ_WAIT=3/23`形成8例。读取等待参数属于测试模型，不是实测DDR延迟。脚本和实际证据归档于`docs/validation/20261023-a61-soc-fetch-boundary`；过程文件放`F:/ARGONAUTICA_work/board_tests/20261023_a61_soc_fetch_boundary`。

提前读取为默认关闭选项：`rv_icache_drm.EARLY_READ`经SoC/FPGA顶层`ICACHE_EARLY_READ`传递，ILA构建可显式设置`RV32_ICACHE_DRM=1 RV32_ICACHE_EARLY_READ=1`。新代码默认0，不代表当前正式位流已经采用。物理候选是否通过以本轮原始报告和实际测试为准。
