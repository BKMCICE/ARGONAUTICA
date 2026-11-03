"""Independent integer Q24 and current 1x1 weight-domain proof; no board IO."""
from pathlib import Path
import argparse,hashlib,itertools,json,random,struct
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[3];w=a.output.resolve();w.mkdir(parents=True,exist_ok=True)
base=r/'models/yolo_fastest_1_1';manifest=json.loads((base/'fixed_manifest.json').read_text(encoding='utf-8'))
weights=(base/'weights_int8.bin').read_bytes();params=(base/'params_q24.bin').read_bytes()
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest().upper()
assert sha(base/'weights_int8.bin')==manifest['weights_sha256'].upper()
assert sha(base/'params_q24.bin')==manifest['params_q24_sha256'].upper()
def scale(v,m):
    product=v*m;n=(abs(product)+8388608)//16777216
    return -n if product<0 else n
def quant(acc,m,b,leaky):
    v=scale(acc,m)
    if not -(2**31-1)<=v<=2**31-1:return 1,0
    v+=b
    if not -2**31<=v<=2**31-1:return 1,0
    if leaky and v<0:v=scale(v,1677722)
    return 0,max(-127,min(127,v))
rows=[];vectors=[]
for l in manifest['layers']:
    if l.get('kernel_size')!=1:continue
    c=l['input_channels_per_group']
    for oc in range(l['output_channels']):
        kernel=struct.unpack_from('<'+str(c)+'b',weights,l['weight_offset']+oc*c)
        m,b=struct.unpack_from('<ii',params,l['param_offset']+oc*8)
        lo=sum(min(-128*k,127*k) for k in kernel);hi=sum(max(-128*k,127*k) for k in kernel)
        scaled=sorted([scale(lo,m),scale(hi,m)]);biased=[x+b for x in scaled]
        assert -2**31<=lo<=hi<2**31 and -2**31<scaled[0]<=scaled[1]<2**31
        assert -2**31<=biased[0]<=biased[1]<2**31
        leaky=int(l.get('activation')=='leaky')
        for v in {lo,hi,0,(lo+hi)//2}:assert quant(v,m,b,leaky)[0]==0;vectors.append((v,m,b,leaky))
        rows.append(dict(layer=l['index'],channel=oc,input_channels=c,accumulator=[lo,hi],multiplier=m,bias=b,rounded=scaled,before_clip=biased,leaky=leaky))
assert rows
for x,m,b,leaky in itertools.product(
    [-2**31,-2**31+1,-1048576,-65537,-8388609,-8388608,-8388607,-255,-129,-128,-127,-3,-1,0,1,3,127,128,129,255,65537,8388607,8388608,8388609,2**31-1],
    [-2**31,-16777217,-16777216,-8388608,-16384,-1,0,1,256,16384,8388608,16777216,16777217,2**31-1],
    [-2**31,-128,-1,0,1,127,2**31-1],[0,1]):vectors.append((x,m,b,leaky))
rng=random.Random(0xa320011)
for _ in range(4096):vectors.append((rng.randrange(-2**31,2**31),rng.randrange(-2**31,2**31),rng.randrange(-2**31,2**31),rng.randrange(2)))
assert len(vectors)<100000
lines=[];errors=0
for x,m,b,leaky in vectors:
    error,value=quant(x,m,b,leaky);errors+=error
    bits=((x&0xffffffff)<<104)|((m&0xffffffff)<<72)|((b&0xffffffff)<<40)|(leaky<<39)|(error<<8)|(value&255)
    lines.append(f'{bits:034x}\n')
(w/'q24_vectors.hex').write_text(''.join(lines),encoding='ascii',newline='\n')
out=dict(result='A32_CURRENT_FIXED_1X1_DOMAIN_PASS',layers=len({x['layer'] for x in rows}),channels=len(rows),weights_sha256=sha(base/'weights_int8.bin'),params_sha256=sha(base/'params_q24.bin'),manifest_sha256=sha(base/'fixed_manifest.json'),accumulator=[min(x['accumulator'][0] for x in rows),max(x['accumulator'][1] for x in rows)],before_clip=[min(x['before_clip'][0] for x in rows),max(x['before_clip'][1] for x in rows)],vectors=len(vectors),rejected_vectors=errors,vector_sha256=sha(w/'q24_vectors.hex'),rows=rows,scope='All signed-int8 inputs and frozen current 1x1 weights/parameters. Raw dot int32, Q24 defined narrowing/negation and bias int32 addition bounds verified per output channel; not a runtime activation-distribution measurement. Generic overflow is rejected, not wrapped. Wide signed32 multiplication plus rounding fits signed64; no support for arbitrary int64 accumulator input.')
(w/'model_domain.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8');print(out['result'],out['layers'],out['channels'],out['accumulator'],out['before_clip'],out['vectors'])
