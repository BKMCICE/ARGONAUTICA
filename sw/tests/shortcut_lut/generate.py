"""Freeze the exact production reference and independent per-shape expectations."""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
def function(source,name):
    m=re.search(r'^static [^\n]+\b'+name+r'\([^\n]*\)\n\{',source,re.M)
    if not m:raise ValueError('Function not found: '+name)
    end=m.end();depth=1
    while depth:
        if source[end]=='{':depth+=1
        elif source[end]=='}':depth-=1
        end+=1
    return source[m.start():end]+'\n'
def q24(value,multiplier):
    p=value*multiplier
    return (p+(1<<23))//(1<<24) if p>=0 else -((-p+(1<<23))//(1<<24))
def signed8(x):return x if x<128 else x-256
def expected(count,index,a,b):
    h=2166136261
    for i in range(count):
        x=signed8(((i*73+index*17)^(i>>8))&255)
        y=signed8((i*151+index*23+5)&255)
        v=max(-127,min(127,q24(x,a)+q24(y,b)))
        h=((h^(v&255))*16777619)&0xffffffff
    return h
def generate(out):
    out.mkdir(parents=True,exist_ok=True)
    source=(ROOT/'sw/yolo_fixed/main.c').read_text(encoding='utf-8-sig').replace('\r\n','\n')
    snippets={n:function(source,n) for n in ['apply_q24','clip8','shortcut_layer']}
    (out/'production_reference.h').write_text(snippets['apply_q24']+snippets['clip8']+
        'static const int8_t *a65_control_source;\nstatic const int8_t *output_of(int index) { (void)index; return a65_control_source; }\n'+snippets['shortcut_layer'],encoding='utf-8',newline='\n')
    cases=[]
    for line in (ROOT/'sw/yolo_fixed/model_graph.h').read_text().splitlines():
        m=re.search(r'/\* layer (\d+) \*/',line)
        if not m:continue
        v=list(map(int,re.findall(r'-?\d+',line.split('/*')[0])))
        if v[0]!=3:continue
        n=v[4]*v[5]*v[6];idx=int(m[1]);cases.append(dict(layer=idx,count=n,a=v[20],b=v[16],expected_fnv1a=expected(n,idx,v[20],v[16])))
    assert len(cases)==18 and max(x['count'] for x in cases)==102400
    h='#ifndef A65_EXPECTED_H\n#define A65_EXPECTED_H\nstatic const uint32_t a65_layers[18] = {'+','.join(str(x['layer']) for x in cases)+'};\n'
    h+='static const uint32_t a65_expected[18] = {'+','.join('0x%08xu'%x['expected_fnv1a'] for x in cases)+'};\n#endif\n'
    h=h.replace('#endif\n','static const uint32_t a65_expected_short[18] = {'+','.join('0x%08xu'%expected(min(x['count'],257),x['layer'],x['a'],x['b']) for x in cases)+'};\n#endif\n')
    (out/'expected.h').write_text(h,encoding='ascii',newline='\n')
    result=dict(result='PRODUCTION_REFERENCE_AND_INDEPENDENT_EXPECTATIONS',cases=cases,
        main_sha256=hashlib.sha256((ROOT/'sw/yolo_fixed/main.c').read_bytes()).hexdigest().upper(),
        graph_sha256=hashlib.sha256((ROOT/'sw/yolo_fixed/model_graph.h').read_bytes()).hexdigest().upper(),
        snippets_sha256={k:hashlib.sha256(v.encode()).hexdigest().upper() for k,v in snippets.items()},
        scope='Reference inner functions verbatim; output_of only supplies the diagnostic source pointer. Oracle uses arbitrary precision signed arithmetic and division, not candidate tables.')
    (out/'generation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args();print(json.dumps(generate(a.out),indent=2))
