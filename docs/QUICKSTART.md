# 源码使用

## 可直接进行的工作

本仓库可用于阅读 CPU、Cache、定点计算、固件调度与图像接口实现，检查模型数据与软件配方，以及在准备相应工具后编译独立软件。完整板级综合与上板前还需恢复缺失的厂商 IP；见 [IP_RESTORE.md](../IP_RESTORE.md)。

分发文件字节、演示应用源文件与模型配方检查：

```bash
python tools/verify_source.py
python demo/software/build.py --check
```

前一条命令只核对当前分发的保存字节，不检查被排除的厂商实现，也不执行板级验证。编译软件需要 xPack RISC-V GCC 15.2.0，支持 RV32IM／ILP32 multilib。输出目录应为新的独立目录：

```text
python demo/software/build.py --toolchain <GCC-bin-directory> --output <new-output-directory>
python demo/software/build.py --component boot --toolchain <GCC-bin-directory> --output <another-new-output-directory>
```

Windows 链接器需要可用的 ASCII 工具链路径。构建脚本保留传入路径的拼写；不要为了运行而在源码中全局替换路径或验收 SHA。构建命令不会访问 JTAG、串口或 Flash。

## 需要自行准备的内容

- 与目标器件适配、具备相应使用授权的 PDS 及厂商仿真／器件库。
- 与原接口参数匹配的 DDR3、PLL、FIFO 等厂商实现；不能用占位模块代替。
- 对具体仿真入口所需的模拟器及裸机工具链进行配置。
- 如果替换模型或参数，重新完成转换、数值对照和硬件行为检查。

PDS 工程和约束保留为设计参考。公开目录中缺失厂商依赖时，直接运行硬件完整性门禁或物理实现流程可能失败，这是导出边界，不代表已有经过验证的替代模块。

## 上板结论

本仓库没有预编译 BIT、应用 ELF／BIN 或组合 Flash 镜像。软件成功编译、某个仿真通过或工程能够打开，都不能替代新硬件的约束、管脚、CDC 和实板检查。原系统的实测范围见 [VALIDATION.md](VALIDATION.md)。
