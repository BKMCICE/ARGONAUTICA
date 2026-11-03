"""A48 isolated eight-output postprocessor and actual-production operator copy.
The A32 scalar quantizer is reused unchanged; A331 raw mode remains intact.
"""
from pathlib import Path
import sys
p=Path(__file__).resolve().parent;r=p.parents[2]
def swap(s,a,b,n=1):
    assert s.count(a)==n,(a,s.count(a),n)
    return s.replace(a,b)
products={}
s=(r/'rtl/periph/ai_conv3x3_quant.v').read_text()
for a,b in [('A32 isolated optional','A48 isolated optional eight-output'),('module ai_conv3x3_quant (','module ai_conv3x3_quant8 ('),("10'h00a","10'h00b"),('cfg_outputs<=4','cfg_outputs<=8'),('[4:0] wanted_mask','[8:0] wanted_mask'),("5'd1<<cfg_outputs","9'd1<<cfg_outputs"),('multipliers[0:3],biases[0:3]','multipliers[0:7],biases[0:7]'),('[3:0] mult_valid,bias_valid','[7:0] mult_valid,bias_valid'),('wanted_mask[3:0]','wanted_mask[7:0]'),('[2:0] param_addr,output_index','[3:0] param_addr,output_index'),('[3:0] pixels,outputs,pixel_index,packed_write,packed_read,packed_count','[3:0] pixels,outputs,pixel_index;\n    reg [4:0] packed_write,packed_read,packed_count'),('packed_words[0:7]','packed_words[0:15]'),('ai_conv3x3_block core','ai_conv3x3_block8 core'),('output_index[1:0]','output_index[2:0]'),("32'h41333231","32'h41343831"),("{16'b0,bias_valid,mult_valid","{8'b0,bias_valid,mult_valid"),("{29'b0,param_addr}","{28'b0,param_addr}"),('param_addr<4','param_addr<8'),('param_addr[1:0]','param_addr[2:0]'),("{28'b0,packed_read}","{27'b0,packed_read}"),('packed_read[2:0]','packed_read[3:0]'),("{28'b0,packed_count}","{27'b0,packed_count}"),('if(wdata<4)begin param_addr<=wdata[2:0]','if(wdata<8)begin param_addr<=wdata[3:0]'),('if(wdata<8)packed_read<=wdata[3:0]','if(wdata<16)packed_read<=wdata[4:0]'),('packed_write[2:0]','packed_write[3:0]')]:
    assert a in s,a;s=s.replace(a,b)
products[r/'rtl/periph/ai_conv3x3_quant8.v']=s

# Keep A48 reproducible after production evolves (A50 adds shared post8).
s=(p/'control_source.inc').read_text();a=s.index('__attribute__((noinline)) static int conv1x1_block(');start=s.index('{',a);end=start+1;depth=1
while depth:depth+=(s[end]=='{')-(s[end]=='}');end+=1
s=s[a:end].replace('static int conv1x1_block(','static int a48_post_block(')
needle='    if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 1u) return AI_BLOCK_HW_ERROR;'
s=swap(s,needle,needle+'''
    if (AI_BLOCK_READ(0x2cu) != 0x41343831u)
        return conv1x1_block(layer,input,output,kernels,params,in_group,out_group);
    if (AI_BLOCK_READ(0x28u) != 0x41333331u) return AI_BLOCK_HW_ERROR;
    AI_BLOCK_WRITE(0x204u,1u|(layer->leaky?2u:0u));''')
s=swap(s,'            AI_BLOCK_WRITE(AI_BLOCK_WADDR, 0u);','            AI_BLOCK_WRITE(AI_BLOCK_WADDR, 0u);\n            AI_BLOCK_WRITE(0x208u,0u);')
needle='                uint32_t oc = group * out_group + oc_base + ch;';assert s.count(needle)==2
s=s.replace(needle,needle+'\n                AI_BLOCK_WRITE(0x20cu,(uint32_t)params[oc*2]);\n                AI_BLOCK_WRITE(0x210u,(uint32_t)params[oc*2+1]);',1)
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
s=swap(s,'    int32_t acc[YOLO_BLOCK8 ? 64 : 32];','')
s=swap(s,'    return AI_BLOCK_OK;','    AI_BLOCK_WRITE(0x204u,0u);\n    return AI_BLOCK_OK;')
products[p/'candidate_block.h']='/* Generated A48 diagnostic: actual A45 validation/cache/packing, post8 transport. */\n'+s+'\n'

s=(p/'../ai_block_post/host_mmio.c').read_text().replace('a32_','a48_')
for a,b in [('w[300]','w[600]'),('r[32]','r[64]'),('wvalid[300]','wvalid[600]'),('qm[4],qb[4],qpacked[8]','qm[8],qb[8],qpacked[16]'),('if(off==0x28)return mode==7?0:0x41333231u;','if(off==0x28)return mode==8?0:0x41333331u;\n    if(off==0x2c)return mode==7||mode==8?0:0x41343831u;'),('value>=4','value>=8'),('qi>=4','qi>=8'),('value>=8)abort();qri','value>=16)abort();qri'),('wi>=300','wi>=(mode==8?300u:600u)'),('o>4','o>(mode==8?4u:8u)')]:
    assert a in s,a;s=s.replace(a,b)
products[p/'host_mmio.c']=s
for name in ['diag.h','host_mmio.h','operator.c','main.c','harness.inc','expected_short.h','Makefile']:
    s=(p/'../ai_block_post'/name).read_text().replace('a32_','a48_').replace('A32_','A48_').replace('ai_block_post','ai_block8_post')
    if name=='Makefile':s=s.replace('CFLAGS += -DA48_SHORT','CFLAGS += -DYOLO_BLOCK8=1 -DA48_SHORT')
    if name=='harness.inc':
        s=swap(s,'((co+3)/4)','((co+7)/8)')
        s=swap(s,'    for(unsigned mode=1;mode<=6;++mode)', '''    a48_reset(8);prepare(1);
    if(a48_control(&l,input+8,prior+8,weights+8,params))return 25;
    a48_reset(8);if(a48_candidate(&l,input+8,actual+8,weights+8,params)||check(&l,0,1)||a48_post_writes||a48_packed_reads)return 26;
    const unsigned cis[]={1,3,4,8,9,10,16,17,120,224,2},cos[]={1,3,4,5,7,8,9,16,24};
    for(unsigned a=0;a<11;++a)for(unsigned b=0;b<9;++b){
        YoloLayer edge=shape(0);edge.groups=1+(a+b)%2;edge.ic=cis[a]*edge.groups;edge.oc=cos[b]*edge.groups;
        edge.ih=2;edge.iw=17;edge.oh=2;edge.ow=17;edge.leaky=(a+b)%2;
        if(host_case(edge,11,1))return 27;++cases;
    }
    for(unsigned mode=1;mode<=6;++mode)''')
        s=s.replace('AI_BLOCK_READ(0x28u)','AI_BLOCK_READ(0x2cu)').replace('0x41333231u','0x41343831u')
    products[p/name]=s

s=(r/'sim/tb/tb_ai_block_post.v').read_text().replace('tb_ai_block_post','tb_ai_block8_post').replace('A32_','A48_')
s=s.replace('.ENABLE_QUANT(1)', '.ENABLE_QUANT(1),.ENABLE_BLOCK8(1)').replace('#(.ENABLE_BLOCK(1)) old','#(.ENABLE_BLOCK(1),.ENABLE_BLOCK8(1)) old')
for a,b in [('raw[0:31],mw[0:3],bw[0:3]','raw[0:63],mw[0:7],bw[0:7]'),('timeout<2000','timeout<10000'),("reset_unit;rd('h28,v)","reset_unit;rd('h28,v);if(v!==32'h41333331||old_data!==32'h41333331)$fatal(1,\"A331 changed\");rd('h2c,v)"),("32'h41333231","32'h41343831"),("10'h00a","10'h00b"),("wr('h208,4)","wr('h208,8)"),("wr('h21c,8)","wr('h21c,16)"),('oi<3','oi<6'),('no=oi==0?1:oi==1?3:4;','case(oi)0:no=1;1:no=3;2:no=4;3:no=5;4:no=7;5:no=8;endcase')]:
    assert a in s,a;s=s.replace(a,b)
products[r/'sim/tb/tb_ai_block8_post.v']=s

for path,data in products.items():
    if '--check' in sys.argv:assert path.read_text()==data,str(path)
    else:path.write_text(data,encoding='utf-8',newline='\n')
print('A48_GENERATED_CHECK_PASS' if '--check' in sys.argv else 'A48_GENERATED_WRITTEN',len(products))
