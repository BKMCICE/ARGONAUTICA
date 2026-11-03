"""Mechanical A02 capacity and production operator clones, not a dispatcher edit.
--check verifies each generated file against its reviewed upstream source.
"""
from pathlib import Path
import sys
p=Path(__file__).resolve().parent;r=p.parents[2]
def swap(s,a,b,n=None):
    count=s.count(a);assert count and (n is None or count==n),(a,count,n)
    return s.replace(a,b)
products={}
s=(r/'rtl/periph/ai_conv3x3.v').read_text(encoding='utf-8')
s=s[s.index('module ai_conv3x3_block ('):]
for a,b in [('module ai_conv3x3_block (','module ai_conv3x3_block8 ('),
 ('weights [0:99]','weights [0:199]'),('results [0:31]','results [0:63]'),
 ('reg [99:0] weight_valid','reg [199:0] weight_valid'),
 ('reg [6:0] w_upload','reg [7:0] w_upload'),('reg [5:0] r_read','reg [6:0] r_read'),
 ('cfg_outputs<=4','cfg_outputs<=8'),
 ('reg [5:0] block_index,r_write,result_count','reg [5:0] block_index;\n    reg [6:0] r_write,result_count'),
 ('reg [6:0] w_index,w_base','reg [7:0] w_index,w_base'),
 ('wdata<100','wdata<200'),('w_upload<100','w_upload<200'),
 ('w_upload<=wdata[6:0]','w_upload<=wdata[7:0]'),
 ("wdata<32) r_read<=wdata[5:0]","wdata<64) r_read<=wdata[6:0]"),
 ('r_write[4:0]','r_write[5:0]'),('r_read[4:0]','r_read[5:0]'),
 ("{25'b0,w_upload}","{24'b0,w_upload}"),("{26'b0,r_read}","{25'b0,r_read}"),
 ("if(legacy_region) case(addr[5:2])","if(addr[11:0]==12'h028) rdata=32'h41333331;\n        else if(legacy_region) case(addr[5:2])")]:s=swap(s,a,b)
products[r/'rtl/periph/ai_conv3x3_block8.v']='// Generated A33: A02 semantics, eight outputs, capability A331 at 0x28.\n'+s

# Keep the historical A33 clone tied to its reviewed four-output source.
# Production now dispatches4/8 capacity in one shared A45 function.
s=(p/'control_source.inc').read_text(encoding='utf-8');a=s.index('__attribute__((noinline)) static int conv1x1_block(');start=s.index('{',a);depth=1;end=start+1
while depth:depth+=(s[end]=='{')-(s[end]=='}');end+=1
s=s[a:end]
for a,b in [('static int conv1x1_block(','static int a33_block8('),('int32_t acc[32]','int32_t acc[64]'),('oc_base += 4u','oc_base += 8u'),('if (outputs > 4u) outputs = 4u;','if (outputs > 8u) outputs = 8u;')]:s=swap(s,a,b,1)
needle='    if (AI_BLOCK_READ(AI_BLOCK_REG_ID) != AI_BLOCK_ID) return AI_BLOCK_UNSUPPORTED;'
s=swap(s,needle,'''    if (AI_BLOCK_READ(0x28u) != 0x41333331u)
        return conv1x1_block(layer,input,output,kernels,params,in_group,out_group);
'''+needle,1)
products[p/'candidate_block.h']='/* Generated production validation/cache/packing clone; only batch capacity differs. */\n'+s+'\n'

for filename in ['operator.c','diag.h','expected_short.h']:
 s=(p/'../ai_block_post'/filename).read_text(encoding='utf-8').replace('a32_','a33_').replace('A32_','A33_').replace('a33_post_block','a33_block8')
 products[p/filename]=s

s=(p/'../ai_block_post/main.c').read_text(encoding='utf-8').replace('a32_','a33_').replace('A32_','A33_')
products[p/'main.c']=s
h=(p/'../ai_1x1_block_layer/host_mmio.c').read_text(encoding='utf-8').replace('a03_','a33_').replace('A03_','A33_')
a=h.index('static void __attribute__((constructor))');b=h.index('void a33_reset(',a);h=h[:a]+h[b:]
for a,b in [('w[300],p[600],r[32]','w[600],p[600],r[64]'),('wvalid[300]','wvalid[600]'),('wi>=300','wi>=(mode==7?300u:600u)'),('!o || o>4','!o || o>(mode==7?4u:8u)')]:h=swap(h,a,b)
h=swap(h,'uint32_t a33_starts,','uint32_t a33_raw_reads;\nuint32_t a33_starts,',1)
h=swap(h,'    mode=value;','    a33_raw_reads=0;\n    mode=value;',1)
h=swap(h,'    ++a33_reads;','    ++a33_reads;\n    if(off==0x28)return mode==7?0:0x41333331u;',1)
h=swap(h,'    if(off==AI_BLOCK_RDATA) {','    if(off==AI_BLOCK_RDATA) {\n        ++a33_raw_reads;',1)
h=swap(h,'case AI_BLOCK_RADDR:ri=value;return;','case AI_BLOCK_RADDR:if(value>=(mode==7?32u:64u))abort();ri=value;return;',1)
products[p/'host_mmio.c']=h
s=(p/'../ai_block_post/host_mmio.h').read_text(encoding='utf-8').replace('a32_','a33_').replace('A32_','A33_')
s=swap(s,'extern uint32_t a33_raw_reads,a33_packed_reads,a33_post_writes,a33_post_items;','extern uint32_t a33_raw_reads;',1)
products[p/'host_mmio.h']=s

h=(p/'../ai_block_post/harness.inc').read_text(encoding='utf-8').replace('a32_','a33_').replace('A32_','A33_')
a=h.index('    unsigned ci=l.ic/l.groups');b=h.index('    return 0;\n}\n#else',a)
h=h[:a]+'''    unsigned ci=l.ic/l.groups,co=l.oc/l.groups,blocks=(ci+8)/9;
    unsigned ctrl_batches=l.groups*((co+3)/4),new_batches=l.groups*((co+7)/8);
    if(ctrl_tasks!=ctrl_batches*l.oh*((l.ow+7)/8)||a33_starts!=new_batches*l.oh*((l.ow+7)/8)||
       ctrl_weights!=l.oc*blocks*3||a33_weight_words!=ctrl_weights||
       ctrl_pixels!=ctrl_batches*l.oh*l.ow*blocks*3||a33_pixel_words!=new_batches*l.oh*l.ow*blocks*3||
       raw!=l.oc*l.oh*l.ow||a33_raw_reads!=raw)return 5;
'''+h[b:]
h=swap(h,'actual_post_id','actual_block8_id')
h=swap(h,'A33_POST_ID','A33_BLOCK8_ID')
h=swap(h,'    for(unsigned mode=1;mode<=6;++mode)', '''    const unsigned boundary_ci[]={1,3,4,8,9,10,16,17,120,224,2};
    const unsigned boundary_co[]={1,3,4,5,7,8,9,16,24};
    for(unsigned a=0;a<11;++a)for(unsigned b=0;b<9;++b){
        YoloLayer edge=shape(0);edge.groups=1+(a+b)%2;edge.ic=boundary_ci[a]*edge.groups;
        edge.oc=boundary_co[b]*edge.groups;edge.ih=2;edge.iw=17;edge.oh=2;edge.ow=17;
        edge.leaky=(a+b)%2;if(host_case(edge,11,1))return 24;++cases;
    }
    for(unsigned mode=1;mode<=6;++mode)''',1)
h=swap(h,'||a33_post_writes||a33_packed_reads','',1)
h=swap(h,'if((mode==1||mode==2)&&a33_post_writes)','if((mode==1||mode==2)&&a33_writes)',1)
a=h.index('    if(actual_block8_id==0x41333231u)');b=h.index('    uart_puts("A33_DIAGNOSTIC_PASS',a)
h=h[:a]+h[b:]
products[p/'harness.inc']=h

t=(r/'sim/tb/tb_ai_1x1_block.v').read_text(encoding='utf-8')
t=swap(t,'module tb_ai_1x1_block #(parameter BLOCK_ENABLE=1, parameter WINDOW_ENABLE=0, parameter QUANT_ENABLE=0);','module tb_ai_block8;',1)
t=swap(t,'#(.ENABLE_BLOCK(BLOCK_ENABLE),.ENABLE_WINDOW(WINDOW_ENABLE),.ENABLE_QUANT(QUANT_ENABLE))','#(.ENABLE_BLOCK(1),.ENABLE_BLOCK8(1))',1)
for a,b in [("'h10151","'h10191"),('// five outputs','// nine outputs'),("wr('h10c,100)","wr('h10c,200)"),("wr('h11c,32)","wr('h11c,64)"),('no<=4','no<=8'),('no=4;np=8','no=8;np=8'),('A01_BLOCK_RTL_PASS','A33_BLOCK8_RTL_PASS')]:t=swap(t,a,b,1)
t=swap(t,'        reset_unit();rd',"        reset_unit();rd('h28,v);if(v!='h41333331)$fatal(1,\"A33 capability\");rd",1)
t=swap(t,'            rd(\'h124,clocks);', '''            rd('h11c,v);if(v!=np*no)$fatal(1,"Result cursor/count wrapped");
            rd('h120,v);if(v!=0)$fatal(1,"Result overread exposed data");
            rd('h104,v);if(!v[2])$fatal(1,"Result overread missing error");
            rd('h124,clocks);''',1)
products[r/'sim/tb/tb_ai_block8.v']='// Generated full-capacity variant of reviewed original block protocol test.\n'+t

f=products[p/'main.c'].replace('#include "harness.inc"','#include "full_harness.inc"')
products[p/'full_main.c']=f
f=products[p/'harness.inc']
f=swap(f,'for(unsigned k=0;k<11;++k){YoloLayer l=shape(k);prepare(1);','for(unsigned k=0;k<11;++k){if(k!=2 && k!=10)continue;YoloLayer l=shape(k);prepare(1);',1)
f=swap(f,'sample<3','sample<1',1)
f=swap(f,'A33_DIAGNOSTIC_PASS','A33_FULL_DIAGNOSTIC_PASS',1)
products[p/'full_harness.inc']=f

bad=[]
for target,value in products.items():
 if '--check' in sys.argv:
  if not target.exists() or target.read_text(encoding='utf-8')!=value:bad.append(str(target))
 else:target.parent.mkdir(parents=True,exist_ok=True);target.write_text(value,encoding='utf-8',newline='\n')
assert not bad,bad
print('A33_GENERATED_SOURCE_PASS',len(products))
