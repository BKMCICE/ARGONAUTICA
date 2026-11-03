# YOLO-Fastest 1.1 模型与量化数据

本目录保留系统所用模型、配置、类别名、量化参数及固定回归数据。来源为 [Yolo-Fastest ModelZoo](https://github.com/dog-qiuqiu/Yolo-Fastest/tree/96a2900d163196c396e73f3fdab04ca4dd9a2f70/ModelZoo/yolo-fastest-1.1_coco)，固定上游提交 `96a2900d163196c396e73f3fdab04ca4dd9a2f70`；原许可文本保留于 `LICENSE`。

| 文件组 | 用途 |
|---|---|
| `yolo-fastest-1.1.cfg`、`.weights`、`coco.names` | 原网络配置、权重和类别名 |
| `manifest.json`、`quant_manifest.json`、`fixed_manifest.json` | 层图、权重偏移和定点参数描述 |
| `weights_int8.bin`、`params_fp32.bin`、`params_q24.bin` | 转换后的权重和参数 |
| `activation_scales_2img.json` | 使用过的标定尺度记录 |
| `dog.jpg`、`dog_chw_int8.bin` | 固定回归输入 |

模型和示例图不是本项目原创数据集。若从上游重新获取、替换或再分发这些材料，应保留其来源、许可和相应身份校验；不把本项目原创部分的许可扩展到模型或数据。

转换与参考代码位于 `tools/`，裸机定点实现位于 `sw/yolo_fixed/` 和演示软件快照。固定图一致性、主机参考和原系统实板验证不等于完整 COCO AP／准确率评测，具体结论见[验证范围](../../docs/VALIDATION.md)。
