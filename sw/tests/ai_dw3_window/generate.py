"""Rebuild auditable copies of A25 validation/quantization, A30 test shapes.
Only the interior submission and bus transport change. --check never writes.
"""
from pathlib import Path
import re,sys
p=Path(__file__).resolve().parent
s=(p/'../../yolo_fixed/dw3x3_rolling.h').read_text(encoding='utf-8')
s=s.replace('YOLO_DW3X3_ROLLING_H','A31_ROLLING_H').replace('conv3x3_rolling','a31_rolling').replace('dw3_','a31_dw3_')
s=s.replace('"../common/ai_mac_block.h"','"../../common/ai_mac_block.h"')
s='/* A31 diagnostic copy: preserved shape checks and Q24; optional window transport. */\n'+s[s.index('#ifndef'):]
a=s.index('static inline int32_t a31_dw3_dot(');b=s.index('static inline int8_t',a)
s=s[:a]+s[b:]
needle='    uint32_t first=(l->pad+s-1)/s;'
assert s.count(needle)==1
s=s.replace(needle,'''    // Probe before any write: an old bitstream uses the original operator.
    if(A31_READ(48)!=0x41333131u)return conv3x3_rolling(l,input,output,weights,params);
    if(A31_READ(0)&1u)return AI_BLOCK_HW_ERROR;
    a31_fault=0;A31_WRITE(52,5);A31_WRITE(28,0);
'''+needle)
s=s.replace('ai_load_1x1_weights(', 'a31_load(').replace('ai_dot3x3_loaded(', 'a31_boundary(')
pattern=r'dest\[ox\]=a31_dw3_quant\((a31_boundary\([^;]+?\)),mult,bias,l->leaky\);'
s,count=re.subn(pattern,r'{int32_t v=\1;if(a31_fault)return a31_fault;dest[ox]=a31_dw3_quant(v,mult,bias,l->leaky);}',s)
assert count==3
a=s.index('            if(s==1){');b=s.index('            for(;ox<l->ow;',a)
s=s[:a]+'''            int32_t acc=a31_seed(a,b,c);
            for(;;){
                if(a31_fault)return a31_fault;
                dest[ox]=a31_dw3_quant(acc,mult,bias,l->leaky);
                if(++ox==last)break;
                r0+=s;r1+=s;r2+=s;
                acc=a31_submit(r0,r1,r2,s);
            }
'''+s[b:]
assert s.count('    return AI_BLOCK_OK;')==1
s=s.replace('    return AI_BLOCK_OK;','''    if(a31_fault)return a31_fault;
    if(A31_READ(52)&18u)return AI_BLOCK_HW_ERROR;
    A31_WRITE(52,4);return AI_BLOCK_OK;''')
products={'candidate_rolling.h':s}
t=(p/'../ai_dw3_q24/main.c').read_text(encoding='utf-8').split('#include "harness.inc"')[0]
t=t.replace('#include "diag.h"','#include "diag.h"\n#include "transport.h"').replace('#include "expected.h"','#include "../ai_dw3_q24/expected.h"\n#include "expected_short.h"')
t=t.replace('a30_', 'a31_').replace('a31_expected','a30_expected').replace('A30_SHORT','A31_SHORT')
t=t.replace('volatile uint32_t a31_result;', 'volatile uint32_t a31_result,a31_phase;')
t=t.replace('#define CAP 1024','#define CAP 32768').replace(',mirror[CAP+16]','')
t=t.replace('||actual[i]!=mirror[i]','').replace('=mirror[i]','')
t=t.replace('    l.oh=', '    l.oh=')
needle=' l.oh=shapes[k][6]?'
assert needle in t
t=t.replace(needle,'''#if A31_SHORT
 if(k==2||k==3){l.ih=l.iw=80;l.ic=l.oc=l.groups=1;l.stride=k==2?1:2;}
#endif
'''+needle)
t=t.replace(' if(k<8&&hash(actual+8,n)!=a30_expected[seed-1][k])return 3;', '''#if A31_SHORT
 if(k<4&&hash(actual+8,n)!=a31_short_expected[k])return 3;
#else
 if(k<8&&hash(actual+8,n)!=a30_expected[seed-1][k])return 3;
#endif''')
t=t.replace('||a31_placebo(&l,input+8,mirror+8,weights+8,params)','')
t=t.replace('||host_ai_calls!=3*l.oc*l.oh*l.ow','||host_ai_calls!=l.oc*l.oh*l.ow')
t=t.replace(' prepare(seed);host_ai_calls=0;', ' prepare(seed);host_ai_calls=0;a31_model_reset(1);')
t=t.replace(' if(oracle(&l)||check(&l,k,seed)', ''' uint32_t slides=0,total=l.oc*l.oh*l.ow;
 for(uint32_t y=0;y<l.oh;++y)for(uint32_t x=1;x<l.ow;++x){
  int32_t yy=(int32_t)(y*l.stride)-(int32_t)l.pad;
  int32_t xx=(int32_t)(x*l.stride)-(int32_t)l.pad;
  if(yy>=0&&yy+2<(int32_t)l.ih&&xx-(int32_t)l.stride>=0&&xx+2<(int32_t)l.iw)slides+=l.oc;
 }
 uint32_t seeds=total-slides;
 if(a31_slides!=slides||a31_stages!=(l.stride==2?slides:0)||a31_seeds!=seeds||
    a31_accums!=total||a31_words!=3+3*l.oc+seeds*4+slides*l.stride)return 4;
 if(oracle(&l)||check(&l,k,seed)''')
t=t.replace(' return a31_candidate(l,input+8,actual+8,weights+8,params);',' return a31_candidate(l,input+8,actual+8,weights+8,params);')
t=t.replace(' if(op==1)return a31_placebo(l,input+8,mirror+8,weights+8,params);\n','')
t=t.replace(' if(op==0)return a31_control(l,input+8,prior+8,weights+8,params);\n return a31_candidate(l,input+8,actual+8,weights+8,params);', ''' a31_phase=op+1;
 int rc=op==0?a31_control(l,input+8,prior+8,weights+8,params):a31_candidate(l,input+8,actual+8,weights+8,params);
 a31_phase=0;return rc;''')
t=t.replace('||a31_placebo(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE','')
t+='\n#include "harness.inc"\n'
products['main.c']=t
# Independent padded CHW and division-Q24 reference for the short RV32 fixture.
def signed(v):return (v+128)%256-128
def scale(v,m):
    p=v*m;q=(abs(p)+8388608)//16777216
    return -q if p<0 else q
hashes=[]
for h,w,c,stride,leaky in [(5,17,2,1,1),(7,19,3,2,0),(80,80,1,1,1),(80,80,1,2,1)]:
    oh=(h-1)//stride+1;ow=(w-1)//stride+1;digest=2166136261
    for ch in range(c):
        m=(-1 if ch&1 else 1)*(16384+ch*29);bias=ch%17-8
        for oy in range(oh):
            for ox in range(ow):
                dot=0
                for ky in range(3):
                    for kx in range(3):
                        y=oy*stride+ky-1;x=ox*stride+kx-1
                        if 0<=y<h and 0<=x<w:
                            dot+=signed((8+(ch*h+y)*w+x)*73+19)*signed((8+ch*9+ky*3+kx)*59+31)
                v=scale(dot,m)+bias
                if leaky and v<0:v=scale(v,1677722)
                v=max(-127,min(127,v));digest=((digest^(v&255))*16777619)&0xffffffff
    hashes.append(digest)
products['expected_short.h']='/* Independent padded CHW/division Q24; generated by generate.py. */\nstatic const uint32_t a31_short_expected[4]={'+','.join(f'0x{x:08x}u' for x in hashes)+'};\n'
for name,data in products.items():
    if '--check' in sys.argv:assert (p/name).read_text(encoding='utf-8')==data,name
    else:(p/name).write_text(data,encoding='utf-8',newline='\n')
print('A31_GENERATED_SOURCE_CHECK_PASS' if '--check' in sys.argv else 'A31_GENERATED_SOURCE_WRITTEN')
