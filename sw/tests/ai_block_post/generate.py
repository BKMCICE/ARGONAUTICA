"""Preserve production validation/packing/cache; change only post transport.
Generate the host transport extension from the original strict A03 model.
--check verifies committed copies and expected padded CHW hashes.
"""
from pathlib import Path
import sys
p=Path(__file__).resolve().parent
s=(p/'../ai_block8/control_source.inc').read_text(encoding='utf-8')
a=s.index('__attribute__((noinline)) static int conv1x1_block(')
# The following function may have attributes; stop at the matching brace instead.
start=s.index('{',a);depth=1;end=start+1
while depth:
    depth+=(s[end]=='{')-(s[end]=='}');end+=1
s=s[a:end].replace('static int conv1x1_block(', 'static int a32_post_block(')
needle='    if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 1u) return AI_BLOCK_HW_ERROR;'
assert s.count(needle)==1
s=s.replace(needle,'''    if (AI_BLOCK_READ(0x28u) != 0x41333231u)
        return conv1x1_block(layer,input,output,kernels,params,in_group,out_group);
'''+needle+'''
    AI_BLOCK_WRITE(0x204u,1u|(layer->leaky?2u:0u));''')
needle='            AI_BLOCK_WRITE(AI_BLOCK_WADDR, 0u);'
assert s.count(needle)==1;s=s.replace(needle,needle+'\n            AI_BLOCK_WRITE(0x208u,0u);')
needle='                uint32_t oc = group * out_group + oc_base + ch;'
assert s.count(needle)==2;s=s.replace(needle,needle+'''
                AI_BLOCK_WRITE(0x20cu,(uint32_t)params[oc*2]);
                AI_BLOCK_WRITE(0x210u,(uint32_t)params[oc*2+1]);''',1)
a=s.index('                    AI_BLOCK_WRITE(AI_BLOCK_RADDR, 0u);');b=s.index('#if YOLO_BLOCK_PHASE_PROFILE\n                    BLOCK_PHASE_END(BP_Q24);',a)
s=s[:a]+'''                    AI_BLOCK_WRITE(0x21cu,0u);
                    for(uint32_t ch=0;ch<outputs;++ch){
                        uint32_t oc=group*out_group+oc_base+ch;
                        int8_t *dest=output+oc*out_plane+oy*layer->ow+ox;
                        uint32_t p=0;
                        for(;p+4u<=pixels;p+=4u){
                            uint32_t word=AI_BLOCK_READ(0x220u);
                            dest[p]=(int8_t)word;dest[p+1]=(int8_t)(word>>8);
                            dest[p+2]=(int8_t)(word>>16);dest[p+3]=(int8_t)(word>>24);
                        }
                        if(p<pixels){uint32_t word=AI_BLOCK_READ(0x220u);
                            for(;p<pixels;++p){dest[p]=(int8_t)word;word>>=8;}
                        }
                    }
                    if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u)return AI_BLOCK_HW_ERROR;
'''+s[b:]
s=s.replace('    int32_t acc[32];','')
assert s.count('    return AI_BLOCK_OK;')==1
s=s.replace('    return AI_BLOCK_OK;','    AI_BLOCK_WRITE(0x204u,0u);\n    return AI_BLOCK_OK;')
products={'candidate_block.h':'/* Generated diagnostic copy, no production dispatcher change. */\n'+s+'\n'}
h=(p/'../ai_1x1_block_layer/host_mmio.c').read_text(encoding='utf-8')
h=h.replace('a03_','a32_').replace('A03_','A32_')
a=h.index('static void __attribute__((constructor))');b=h.index('void a32_reset(',a)
h=h[:a]+h[b:]
h=h.replace('uint32_t a32_starts,', '''uint32_t a32_raw_reads,a32_packed_reads,a32_post_writes,a32_post_items;
static uint32_t qm[4],qb[4],qpacked[8],qi,qri,qwords,qenabled,qleaky,qmv,qbv;
static int32_t qscale(int32_t x,int32_t m){int64_t product=(int64_t)x*m;
 int64_t n=((product<0?-product:product)+8388608)/16777216;
 return(int32_t)(product<0?-n:n);}
static int post(unsigned n,unsigned o){
 qwords=qri=0;
 for(unsigned oc=0;oc<o;++oc){
  if(!(qmv&(1u<<oc))||!(qbv&(1u<<oc)))return 1;
  for(unsigned p=0;p<n;p+=4){uint32_t word=0;
   for(unsigned b=0;b<4&&p+b<n;++b){int64_t product=(int64_t)(int32_t)r[oc*n+p+b]*(int32_t)qm[oc];
    int64_t scaled=((product<0?-product:product)+8388608)/16777216;if(product<0)scaled=-scaled;
    if(scaled< -2147483647LL||scaled>2147483647LL)return 1;
    int64_t wide=scaled+(int32_t)qb[oc];if(wide< -2147483648LL||wide>2147483647LL)return 1;
    int32_t v=(int32_t)wide;if(qleaky&&v<0)v=qscale(v,1677722);
    if(v>127)v=127;if(v< -127)v=-127;
    word|=(uint32_t)(uint8_t)v<<(8*b);++a32_post_items;
   }qpacked[qwords++]=word;
  }
 }return 0;
}
uint32_t a32_starts,''')
h=h.replace('    mode=value;','    qi=qri=qwords=qenabled=qleaky=qmv=qbv=0;\n    a32_raw_reads=a32_packed_reads=a32_post_writes=a32_post_items=0;\n    mode=value;')
h=h.replace('    ++a32_reads;', '''    ++a32_reads;
    if(off==0x28)return mode==7?0:0x41333231u;
    if(off==0x220){if(!(status&2)||(status&1)||qri>=qwords)abort();
        ++a32_packed_reads;uint32_t v=qpacked[qri++];if(mode==5)status|=4;return v;}''')
h=h.replace('    if(off==AI_BLOCK_RDATA) {','    if(off==AI_BLOCK_RDATA) {\n        ++a32_raw_reads;')
h=h.replace('    if(status&1) abort();','''    if(status&1) abort();
    if(off>=0x200&&off<0x300){++a32_post_writes;
        switch(off){
        case 0x204:if(value>3)abort();qenabled=value&1;qleaky=(value>>1)&1;qmv=qbv=qwords=qri=0;return;
        case 0x208:if(value>=4)abort();qi=value;qmv=qbv=0;return;
        case 0x20c:if(qi>=4)abort();qm[qi]=value;qmv|=1u<<qi;qbv&=~(1u<<qi);return;
        case 0x210:if(qi>=4||!(qmv&(1u<<qi)))abort();qb[qi]=value;qbv|=1u<<qi++;return;
        case 0x21c:if(value>=8)abort();qri=value;return;
        default:abort();
        }
    }''')
h=h.replace('host_ai_calls+=o*n*b;words=o*n;status=2;return;', 'host_ai_calls+=o*n*b;words=o*n;status=2;\n            if(qenabled&&post(n,o))status=6;return;')
products['host_mmio.c']=h
# Test geometry and frozen full-size hashes are shared with A28. Keep an
# independent padded-CHW/division oracle; only short spatial extents change.
t=(p/'../ai_pdata_reuse/main.c').read_text(encoding='utf-8')
t=t[:t.index('static int store_tests(')]
t=t.replace('#include "expected.h"','#include "../ai_pdata_reuse/expected.h"\n#include "expected_short.h"')
t=t.replace('"../ai_1x1_block_layer/host_mmio.h"','"host_mmio.h"').replace('a28_','a32_').replace('a32_expected','a28_expected').replace('A28_SHORT','A32_SHORT')
t=t.replace('volatile uint32_t a32_result;','volatile uint32_t a32_result,a32_phase;')
t=t.replace('#define IN_CAP 512','#define IN_CAP 4096').replace('#define OUT_CAP 512','#define OUT_CAP 9216').replace('#define W_CAP 512','#define W_CAP 32768')
needle='    l.oh=(l.ih-1)/l.stride+1;'
t=t.replace(needle,'''#if A32_SHORT
    if(k==2||k==3||k==8||k==9||k==10){l.ih=2;l.iw=17;}
#endif
'''+needle)
needle='    if(index<11&&hash(actual+8,n)!=a28_expected[seed-1][index])return 3;'
assert needle in t
t=t.replace(needle,'''#if A32_SHORT
    if(index<11&&hash(actual+8,n)!=a32_short_expected[index])return 3;
#else
'''+needle+'\n#endif')
products['main.c']=t+'\n#include "harness.inc"\n'
def scale(x,m):
    product=x*m;q=(abs(product)+8388608)//16777216
    return -q if product<0 else q
shapes=[(2,9,10,5,1,1,1),(3,7,17,9,1,1,1),(2,17,120,255,1,1,1),
 (2,17,16,96,1,1,1),(5,19,18,10,2,2,0),(1,1,224,7,1,1,1),
 (3,11,1,1,1,1,0),(3,17,9,8,1,1,1),(2,17,4,24,1,1,1),(2,17,8,8,1,1,1),(2,17,120,120,1,1,1)]
signed=lambda n:(n+128)%256-128;expected=[]
for h,w,ic,oc,g,s,leaky in shapes:
    oh=(h-1)//s+1;ow=(w-1)//s+1;ci=ic//g;co=oc//g;digest=2166136261
    for o in range(oc):
        m=(-1 if o&1 else 1)*(16384+o*29);bias=o%17-8
        for y in range(oh):
            for x in range(ow):
                acc=sum(signed((8+((o//co)*ci+c)*h*w+y*s*w+x*s)*73+19)*signed((8+o*ci+c)*59+31) for c in range(ci))
                value=scale(acc,m)+bias
                if leaky and value<0:value=scale(value,1677722)
                value=max(-127,min(127,value));digest=((digest^(value&255))*16777619)&0xffffffff
    expected.append(digest)
products['expected_short.h']='/* Independent CHW/division oracle generated by generate.py. */\nstatic const uint32_t a32_short_expected[11]={'+','.join(f'0x{x:08x}u' for x in expected)+'};\n'
for name,data in products.items():
    if '--check' in sys.argv:assert (p/name).read_text(encoding='utf-8')==data,name
    else:(p/name).write_text(data,encoding='utf-8',newline='\n')
print('A32_GENERATED_SOURCE_CHECK_PASS' if '--check' in sys.argv else 'A32_GENERATED_SOURCE_WRITTEN')
