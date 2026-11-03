"""Run ordinary and ASan/UBSan C checks; native time is not RV32 performance."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,sys
from generate import generate
p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[3];w=a.out.resolve();w.mkdir(parents=True,exist_ok=True)
if w.drive.upper()!='F:':raise ValueError('Keep process files on F:')
generate(w/'generated')
linux=lambda p:'/mnt/'+p.drive[0].lower()+p.as_posix()[2:]
sources=[r/'sw/tests/shortcut_lut/test_native.c',r/'sw/tests/shortcut_lut/operator.c',r/'sw/common/int8_shortcut_lut.h',r/'sw/yolo_fixed/main.c',r/'sw/yolo_fixed/model_graph.h',w/'generated/production_reference.h']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();bound={str(p):sha(p) for p in sources}
results=[]
for mode in ['normal','sanitized']:
    args=['-std=c11','-O2','-g','-Wall','-Wextra','-Werror','-I'+linux(w/'generated')]
    if mode=='sanitized':args+=['-fsanitize=address,undefined','-fno-omit-frame-pointer']
    binary=w/('native_'+mode)
    with (w/(mode+'_build.log')).open('xb') as log:
        subprocess.run(['wsl.exe','-d','Ubuntu-24.04','--','env','TMPDIR=/mnt/f/ARGONAUTICA_work/tmp','gcc',*args,*[linux(x) for x in sources[:2]],'-o',linux(binary)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=90)
    with (w/(mode+'_run.log')).open('xb') as log:
        subprocess.run(['wsl.exe','-d','Ubuntu-24.04','--','env','TMPDIR=/mnt/f/ARGONAUTICA_work/tmp','ASAN_OPTIONS=detect_leaks=1:halt_on_error=1','UBSAN_OPTIONS=halt_on_error=1',linux(binary)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=90)
    text=(w/(mode+'_run.log')).read_text();assert 'A65_NATIVE_PASS' in text and 'FAIL' not in text
    results.append(dict(mode=mode,result='PASS',summary=text.strip()));print(text.strip(),flush=True)
assert bound=={str(p):sha(p) for p in sources}
(w/'native_summary.json').write_text(json.dumps(dict(result='PASS',runs=results,source_files=bound,scope='Exact C semantics, all int8 pairs for18 model multiplier pairs plus12 stress pairs, full counts and tails/exact alias. Not board or RV32 timing.'),indent=2)+'\n')
