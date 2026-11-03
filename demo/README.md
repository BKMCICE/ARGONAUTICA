# 演示系统源码

本目录保留原 HDMI 自动识别系统的软件源快照，以及可展示的硬件、约束与工程内容。原系统能够从 Flash 启动，采集 320×320 模型帧、运行 YOLO，并在文字结果页保持 3 秒后进入下一轮。

此目录已排除厂商受限 IP 和预编译镜像，不能当作完整可直接上板的比赛工程。尤其不要直接把缺件工程通过打开或源码查看解释为综合／时序通过。

## 软件入口

```text
python tools/verify_source.py
python demo/software/build.py --check
python demo/software/build.py --toolchain <GCC-bin-directory> --output <new-output-directory>
```

软件配方使用 RV32IM／ILP32 和 RISC-V GCC 15.2.0。构建脚本不访问硬件；软件源检查和编译均不能恢复缺失的 DDR3／PLL 实现。完整系统原先的软件重建与有限实板结果见[验证范围](../docs/VALIDATION.md)。

## 硬件入口

`hardware/build_src/` 中保留项目 RTL 与接口逻辑，`hardware/pds/` 和 `hardware/inputs/` 保留可展示的配方及约束。厂商依赖恢复前，这些入口是设计参考，不能独立完成与原配置相同的板级构建。恢复流程及限制见[IP 恢复说明](../IP_RESTORE.md)。

软件来源记录仅对应当前保留的软件输入，保存字节校验不包含被排除的厂商实现。不能用缺失文件的源码导出替代完整系统的原始证据。重新生成硬件后必须重新验证时序、管脚和实际行为。
