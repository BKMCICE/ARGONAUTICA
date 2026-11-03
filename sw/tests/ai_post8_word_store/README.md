# A79 post8 对齐字写回隔离对照

不修改生产 C、分派、模型、RTL 或 PDS。`generate.py` 对照冻结 A75 生产源，机械生成一份仅改函数名的 placebo，以及只替换 packed 输出存储循环的候选；逆向替换必须逐字相同。

候选仅当 count=4 且目的地址按4字节对齐，在小端平台使用常量长度 builtin memcpy，保留字符数组别名语义；其余保持逐字节写回。10像素行宽的奇数行及整个未对齐张量均须运行时判断，不能由 arena 对齐推断所有行对齐。

```powershell
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_post8_word_store/generate.py --check
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_post8_word_store/run_host.py --out F:/ARGONAUTICA_work/board_tests/a79_recheck/rtl --mode 0
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_post8_word_store/run_host.py --out F:/ARGONAUTICA_work/board_tests/a79_recheck/rtl --mode 0 --sanitize
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_post8_word_store/run_host.py --out F:/ARGONAUTICA_work/board_tests/a79_recheck/rtl --mode 1
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_post8_word_store/run_host.py --out F:/ARGONAUTICA_work/board_tests/a79_recheck/rtl --mode 2
```

mode0为实际post8 RTL，mode1/2分别为实际旧raw8/raw4 RTL。每种164完整算子、160直接存储案例；独立CHW/int64/除法Q24、三方完整输出/哨兵、全部MMIO写序列/读次数、输入只读、缓存/重叠/参数保护及第一/第二任务错误。native时间不代表RV32或实板速度。

目标三方基准使用相同输入/输出/缓存及全部校验、cache构建、权重参数、传输、等待、读回成本；每形状三者先各预热一次，再六种次序各一次。target禁用IPA相同代码合并，须保留三个独立函数；control/placebo机器字在规范化外部JAL后相同。native验证允许编译器折叠相同placebo，不使用native计时。

```powershell
. ./tools/env.ps1
make -B -C sw/tests/ai_post8_word_store A79_FULL=1 BUILD=F:/ARGONAUTICA_work/board_tests/a79_recheck/full
E:/Python3.13.5/python.exe -X utf8 -B sw/tests/ai_post8_word_store/audit_elf.py --out F:/ARGONAUTICA_work/board_tests/a79_recheck --variant full
```

`generate_expected.py` 独立生成固定合成CHW输入的完整输出FNV与SHA。全版含160×160小通道、40×40/20×20宽通道、10×10尾部/奇数行、整体未对齐负对照、分组stride2和uncached路径。所有算子及raw回退共享TCM；独立实验布局不证明生产TCM可容纳，也不等于整网或AP成绩。详见最终A79归档与接手点。
