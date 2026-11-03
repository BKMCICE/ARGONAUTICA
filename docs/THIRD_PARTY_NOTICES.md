# 第三方代码与版权

本仓库包含项目编写的处理器、加速器和软件，也包含有独立来源的模型、基准测试和测试环境。项目原创部分尚未指定统一开源许可证；不能把源码可见解释为全仓 MIT 授权。各文件的原版权头、LICENSE 和适用条件继续保留。

| 组件 | 来源 | 许可证据与说明 |
|---|---|---|
| YOLO-Fastest 1.1 COCO | [上游 ModelZoo](https://github.com/dog-qiuqiu/Yolo-Fastest/tree/96a2900d163196c396e73f3fdab04ca4dd9a2f70/ModelZoo/yolo-fastest-1.1_coco)，固定提交 `96a2900d163196c396e73f3fdab04ca4dd9a2f70` | 保留 `models/yolo_fastest_1_1/LICENSE`。原模型、示例图及量化派生数据不是本项目原创数据集，获取和再分发应遵循其来源条件。 |
| CoreMark | [EEMBC/coremark](https://github.com/eembc/coremark)，来源提交 `1f483d5b8316753a742cbf5590caf5bd0a4e4777` | `third_party/coremark/LICENSE.md` 包含 Apache License 2.0 与 CoreMark Acceptable Use Agreement。软件许可和 CoreMark 名称／成绩使用条件分别适用。 |
| RISC-V 测试 | [riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests)，来源提交 `d44511022b356a341a2430cfd65f894b77c35f36` | 保留 `third_party/riscv-tests/LICENSE` 和 `third_party/riscv-tests/env/LICENSE`，以及各子目录自己的声明。 |
| Pango 开发板 IP | PDS IP Generator 与开发板配套资料 | 原完整工程中的 DDR3、PLL、FIFO 等实现含 proprietary／授权条件，未作为本仓库可公开源码分发；不得用本项目声明替代厂商许可。 |
| PDS、编译器及厂商库 | 各自官方安装渠道 | 安装程序、个人许可证、工具凭据和完整厂商软件包不在本仓库中分发。 |

本文件用于帮助定位来源，不替代原许可证。不能把项目一部分的许可扩展到另一部分，也不能把生成代码、模型数据或板卡 IP 自动视作无版权限制。受限板级依赖的恢复方式见 [IP_RESTORE.md](../IP_RESTORE.md)。
