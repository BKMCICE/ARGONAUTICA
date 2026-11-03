"""Extract exact production functions; native/sanitizer values are not board timings."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os,subprocess
p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args();w=a.out.resolve();r=Path(__file__).resolve().parents[3]
assert w.drive.upper()=='F:';w.mkdir(exist_ok=True,parents=True);g=w/'native_generated';g.mkdir(exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
linux=lambda p:'/mnt/'+p.drive[0].lower()+p.resolve().as_posix()[2:]
spec=importlib.util.spec_from_file_location('extract',r/'sw/tests/shortcut_lut/generate.py');extract=importlib.util.module_from_spec(spec);spec.loader.exec_module(extract)
source=(r/'sw/yolo_fixed/main.c').read_text(encoding='utf-8-sig')
snippets=''.join(extract.function(source,n) for n in ['apply_q24','clip8','passthrough_layer'])
(g/'production_reference.h').write_text(snippets,encoding='utf-8',newline='\n')
for name,flag in [('control',0),('candidate',1)]:
    (g/(name+'.c')).write_text('#include "model_graph.h"\n#define YOLO_IDENTITY_FASTPATH '+str(flag)+'\n#include "production_reference.h"\nvoid a68_'+name+'(const YoloLayer *l,const int8_t *i,int8_t *o) {passthrough_layer(l,i,o);}\n',encoding='utf-8',newline='\n')
files=[r/'sw/yolo_fixed/main.c',r/'sw/yolo_fixed/model_graph.h',r/'sw/tests/identity_passthrough/test_native.c',Path(__file__),r/'sw/tests/shortcut_lut/generate.py',*g.iterdir()]
bound={str(x):sha(x) for x in files};results=[]
for mode in ['normal','sanitized']:
    flags=['-std=c11','-O2','-g','-Wall','-Wextra','-Werror','-Wno-unused-const-variable','-I'+linux(r/'sw/yolo_fixed'),'-I'+linux(g)]
    if mode=='sanitized':flags+=['-fsanitize=address,undefined','-fno-omit-frame-pointer','-fno-sanitize-recover=all']
    binary=w/('native_'+mode)
    with (w/(mode+'_build.log')).open('xb') as log:
        subprocess.run(['wsl.exe','-d','Ubuntu-24.04','--','env','TMPDIR=/mnt/f/ARGONAUTICA_work/tmp','gcc',*flags,linux(g/'control.c'),linux(g/'candidate.c'),linux(r/'sw/tests/identity_passthrough/test_native.c'),'-o',linux(binary)],stdout=log,stderr=subprocess.STDOUT,check=True)
    with (w/(mode+'_run.log')).open('xb') as log:
        subprocess.run(['wsl.exe','-d','Ubuntu-24.04','--','env','TMPDIR=/mnt/f/ARGONAUTICA_work/tmp','ASAN_OPTIONS=detect_leaks=1:halt_on_error=1','UBSAN_OPTIONS=halt_on_error=1',linux(binary)],stdout=log,stderr=subprocess.STDOUT,check=True)
    raw=(w/(mode+'_run.log')).read_text();assert raw.startswith('A68_NATIVE_PASS cases=116 ') and 'model_layers=20' in raw
    results.append(dict(mode=mode,result='PASS',summary=raw.strip()));print(raw.strip(),flush=True)
assert results[0]['summary']==results[1]['summary'] and bound=={str(x):sha(x) for x in files}
(w/'native_summary.json').write_text(json.dumps(dict(result='PASS',runs=results,source_files=bound,scope='Exact extracted production0/1 C functions, all256 INT8 codes including-128, all20 real passthrough shapes,12 coefficient sets/8 tails/exact aliases, readonly input and output guards. Not a target performance result.'),indent=2)+'\n',encoding='utf-8')
