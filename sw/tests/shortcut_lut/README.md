# A65：残差INT8量化查表隔离原型

该实验只改变shortcut的CPU定点量化方式：每次调用先为两组signed32 Q24乘数各生成256项int16表，再按INT8输入查表、相加并裁剪到[-127,127]。新表由调用者提供的1024B DDR scratch持有，不使用新的乘法硬件或MMIO。不缓存跨层乘数，也不省略建表成本。尚未接入生产YOLO，普通固件及当前配置没有变化。

每个INT8与signed32乘数的乘积绝对值最多2^38；按原半值远离零的Q24舍入后绝对值<=16384，故表项可无损保存在int16；两项相加放int32，再做原裁剪。不能提前把每个表项裁剪到INT8，否则取消量会改变输出。

生产`apply_q24`、`clip8`和`shortcut_layer`由`generate.py`逐字提取并哈希绑定，诊断`output_of`只提供源指针；不为控制路径添加量化或额外循环。候选和控制读取同一输入，输出校验在计时外。输入为预先规定的混合signed INT8模式，使用全部18个真实层的原空间/通道和Q24系数，不冒称真实网络激活分布。完整算子计时包括每次512项建表、全部元素和函数调用，不能只计查表循环。

普通C及ASan/UBSan核验18组模型系数的全部65536种输入对、12组极值/舍入系数的全部输入对、原尺寸、短尾、零长度、只读输入、精确原位别名和输出/scratch哨兵；独立oracle用int64/整数除法实现舍入。只支持独立缓冲或完整同址，不支持部分交叠。scratch与张量必须分离且由当前调用者独占；无动态分配。

## 复跑

先创建新的F盘工作批次，不覆盖冻结日志：

```powershell
$out = 'F:\ARGONAUTICA_work\board_tests\a65_replay_new'
& 'E:\Python3.13.5\python.exe' -X utf8 -B .\sw\tests\shortcut_lut\run_native.py --out $out
. .\tools\env.ps1
make -B -C sw/tests/shortcut_lut "BUILD=$out/short" "A65_GENERATED=$out/generated" A65_FULL=0
make -B -C sw/tests/shortcut_lut "BUILD=$out/full" "A65_GENERATED=$out/generated" A65_FULL=1
& 'E:\Python3.13.5\python.exe' -X utf8 -B .\sw\tests\shortcut_lut\audit.py --out $out
& 'E:\Python3.13.5\python.exe' -X utf8 -B .\sw\tests\shortcut_lut\run_soc.py --out $out
& 'E:\Python3.13.5\python.exe' -X utf8 -B .\sw\tests\shortcut_lut\run_soc.py --out $out --full
```

本机原生测试借用已有Ubuntu-24.04的GCC，TEMP/TMP/TMPDIR及所有构建输出放F盘。诊断固件保留24KiB TCM代码、8KiB栈与256B保护；新ELF逐一重做栈/内存审计，不能套用正式固件界。SoC仿真显式使用当前early1/DRM1/tags2/regfile1/BTB1、2MiB DDR模型，监视越界、异常、AI MMIO及主程序/栈检查返回。短版只检查257元素，建表成本占比较高，不能用它预测全尺寸收益。相同的缓存模拟器在短/完整版之间按源码/二进制哈希绑定后复用。

原始数据用`summarize.py`独立重算18×3个完整形状的周期。原生执行时间不用于性能比较，RTL周期不当作板上速度；是否整网集成取决于原尺寸及实板结果、TCM和新ELF栈/内存门槛。当前正式硬件/固件/配置JSON均不因本隔离实验自动改变。
