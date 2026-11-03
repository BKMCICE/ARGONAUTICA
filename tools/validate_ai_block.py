"""Run the bounded A01 RTL contract and legacy compatibility tests.
Requires iverilog/vvp on PATH; all generated files go to a new --output directory.
No board access, vendor synthesis, downloads, or network operations.
"""
from pathlib import Path
import argparse,hashlib,json,os,subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();r=Path(__file__).resolve().parents[1];out=a.output.resolve()
out.mkdir(parents=True,exist_ok=False)
os.environ['TEMP']=str(out);os.environ['TMP']=str(out)
sha=lambda b:hashlib.sha256(b).hexdigest().upper()
def execute(args,log,success=True):
 with (out/log).open('wb') as f:ret=subprocess.run(args,cwd=r,stdout=f,stderr=subprocess.STDOUT)
 raw=(out/log).read_bytes()
 assert (ret.returncode==0)==success,(args,ret.returncode,raw[-2000:])
 return raw
rtl=r/'rtl/periph/ai_conv3x3.v';unit=r/'sim/tb/tb_ai_1x1_block.v';legacy=r/'sim/tb/tb_ai_conv3x3.v'
miter=r/'sim/tb/tb_ai_block_legacy_miter.v'
source={f.relative_to(r).as_posix():sha(f.read_bytes()) for f in [rtl,unit,legacy,miter,Path(__file__).resolve()]}
source_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip()
for enable in [1,0,2]:
 binary=out/f'unit_{enable}.vvp'
 execute(['iverilog','-g2012','-s','tb_ai_1x1_block',f'-Ptb_ai_1x1_block.BLOCK_ENABLE={enable}','-o',str(binary),str(unit),str(rtl)],f'unit_{enable}_compile.log')
 raw=execute(['vvp',str(binary)],f'unit_{enable}.log',enable==1)
 assert (b'A01_BLOCK_RTL_PASS cases=704 dots=84600' in raw) if enable==1 else ((b'ID mismatch' if enable==0 else b'Optional AI modes require block=1, binary flags and exclusive window mode') in raw)
for enable in [0,1]:
 text=legacy.read_text().replace('ai_conv3x3 dut (',f'ai_conv3x3 #(.ENABLE_BLOCK({enable})) dut (')
 tb=out/f'legacy_{enable}.v';tb.write_text(text,encoding='utf-8',newline='\n');binary=out/f'legacy_{enable}.vvp'
 execute(['iverilog','-g2012','-s','tb_ai_conv3x3','-o',str(binary),str(tb),str(rtl)],f'legacy_{enable}_compile.log')
 assert b'AI_CONV_PASS' in execute(['vvp',str(binary)],f'legacy_{enable}.log')
# Immutable committed original; retain this input for a history-independent replay.
ref=subprocess.check_output(['git','show','88f662e9d3aba12d3facbbba75d8dea774c7774c:rtl/periph/ai_conv3x3.v'],cwd=r)
reftext=ref.decode().replace('module ai_conv3x3 (','module ai_conv3x3_reference (',1)
refpath=out/'legacy_reference.v';refpath.write_text(reftext,encoding='utf-8',newline='\n')
miter=r/'sim/tb/tb_ai_block_legacy_miter.v';binary=out/'miter.vvp'
execute(['iverilog','-g2012','-s','tb_a01_legacy_miter','-o',str(binary),str(miter),str(refpath),str(rtl)],'miter_compile.log')
assert b'A01_DEFAULT_LEGACY_MITER_PASS cycles=20000' in execute(['vvp',str(binary)],'miter.log')
assert source=={f.relative_to(r).as_posix():sha(f.read_bytes()) for f in [rtl,unit,legacy,miter,Path(__file__).resolve()]},'Source changed during tests'
report=dict(result='A01_RTL_CONTRACT_AND_LEGACY_PASS',source_commit=source_commit,source_files=source,baseline_commit='88f662e9d3aba12d3facbbba75d8dea774c7774c',baseline_rtl_sha256=sha(ref),cases=704,raw_dot_count=84600,default_miter_cycles=20000,disabled_negative_control='EXPECTED_ID_FAILURE',invalid_parameter='EXPECTED_REJECTION',scope='RTL simulation only; no PDS, physical timing or YOLO performance claim.')
(out/'result.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(report['result'])
