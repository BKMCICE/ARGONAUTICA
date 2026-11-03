# A74：独立5×5固定窗口打包对照

这是实验目录，生产源码、转发合同、PDS和当前A61＋A71机器配置不变。控制直接调用当前生产conv5x5_block，候选由generate.py绑定归一化源SHA后派生，除函数名外只将dw5_pack5调用替换为a74_pack5，能力/错误处理、权重驻留、post8/raw回退、量化与读回代码逐字保留。

内部合法5×5窗口的3组9/9/7字节用明确坐标和无对齐要求的字节读构造3个小端字；边界、裁剪或非标准first/count仍调用原打包函数。每个输出仍上传9个PDATA字，任务/点积数不减少，无新DMA或硬件。当前正式汇编在内部循环b8f8/b934仍有除5乘高与取模寻址，b97c回跳逐字节循环；本实验检查完整函数而非仅比这些指令。

run_host.py让软件驱动当前实际外围RTL，比较完整输出、权重/像素/形状上传trace和独立CHW/int64/整数除法Q24。包含全部1～8尾批、裁剪、stride/pad、小形状、真实20×20×120和10×10×96、全-128、输入/参数只读、输出哨兵、40,950个直接打包用例；超时/迟错误、第二任务错误均不得重试或回退。普通/ASan和raw8/raw4分别记录；主机耗时不用于目标性能。

run_soc.py使用现有CPU/缓存/DDR及外围RTL，测试包装只加观测，ICACHE_EARLY_READ1/BTB1/ICACHE_DRM1/DCACHE_TAG_STORAGE2/REGFILE_STORAGE1与当前A61一致，DDR模型2MiB。控制和候选都用同一post8或raw能力，不把旧raw控制和新post8候选混成打包收益。

独立诊断将两个算子及共用raw-store都放TCM，使用自己的link.ld，不修改生产链接脚本。新ELF必须单独审核栈/内存，完整算子计时包含验证、权重/参数、打包、全部MMIO/等待和量化/写回；预热后交替三组。数据为可复现合成值，非整网激活或AP样本，隔离TCM放置和缓存布局不等于生产集成性能。小空间/边界密集形状可变慢，负结果必须保留。

```powershell
python -X utf8 -B sw/tests/ai_dw5_pack_fast/generate.py --check
python -X utf8 -B sw/tests/ai_dw5_pack_fast/run_host.py --out F:/ARGONAUTICA_work/board_tests/a74_fresh --mode 0
python -X utf8 -B sw/tests/ai_dw5_pack_fast/run_host.py --out F:/ARGONAUTICA_work/board_tests/a74_fresh --mode 0 --sanitize
python -X utf8 -B sw/tests/ai_dw5_pack_fast/run_host.py --out F:/ARGONAUTICA_work/board_tests/a74_fresh --mode 1
python -X utf8 -B sw/tests/ai_dw5_pack_fast/run_host.py --out F:/ARGONAUTICA_work/board_tests/a74_fresh --mode 2
python -X utf8 -B sw/tests/ai_dw5_pack_fast/run_soc.py --out F:/ARGONAUTICA_work/board_tests/a74_fresh --mode 0
```

使用新的F盘批次；更改源码/flags/编译器后不能复用旧镜像。脚本不自动连接实体板、运行PDS或修改正式配置。进一步生产集成须先有完整算子实测收益，再默认关闭、flag0复现、转发合同重新审核、新实际ELF预算、131层全张量、整网三轮和多图/新显示。
