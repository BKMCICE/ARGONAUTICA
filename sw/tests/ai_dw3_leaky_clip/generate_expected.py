from pathlib import Path
import argparse,json,hashlib,numpy as np
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();d=Path(__file__).resolve().parent
shapes=[(80,80,32,1,1,1,0,0,0),(160,160,8,1,1,1,0,0,0),(40,40,48,1,1,1,0,0,0),(7,19,3,2,1,0,0,0,0),(5,9,1,1,2,0,3,4,0),(1,1,2,1,1,1,0,0,0),(80,80,32,1,1,1,0,0,1),(5,17,2,1,1,1,0,0,0)]
def rounded(v,m):
 p=v*m;n=(np.abs(p)+8388608)//16777216;return np.where(p<0,-n,n)
rows=[]
for k,(h,w,c,s,pad,leaky,ch,cw,off) in enumerate(shapes):
 oh=ch or (h+2*pad-3)//s+1;ow=cw or (w+2*pad-3)//s+1
 x=(((np.arange(c*h*w,dtype=np.int64)+8+off)*73+19+128)%256-128).reshape(c,h,w)
 weights=(((np.arange(c*9,dtype=np.int64)+8)*59+31+128)%256-128).reshape(c,3,3)
 padded=np.pad(x,((0,0),(pad,pad),(pad,pad)));dot=np.zeros((c,oh,ow),dtype=np.int64)
 for y in range(3):
  for xx in range(3):dot+=padded[:,y:y+oh*s:s,xx:xx+ow*s:s]*weights[:,y,xx,None,None]
 for co in range(c):
  v=rounded(dot[co],(-1 if co&1 else 1)*(16384+co*29))+(co%17)-8
  if leaky:v=np.where(v<0,rounded(v,1677722),v)
  dot[co]=np.clip(v,-127,127)
 raw=dot.astype('int8').tobytes();fnv=2166136261
 for b in raw:fnv=((fnv^b)*16777619)&0xffffffff
 rows.append(dict(shape=k,fnv1a=f'{fnv:08x}',output_sha256=hashlib.sha256(raw).hexdigest().upper(),bytes=len(raw)))
header='/* Independent NumPy CHW/int64/division-Q24 whole outputs. */\nstatic const uint32_t a91_expected[8]={'+','.join('0x'+x['fnv1a']+'u' for x in rows)+'};\n'
if a.check:assert (d/'expected.h').read_text()==header
else:(d/'expected.h').write_text(header,encoding='utf-8',newline='\n')
print(json.dumps(dict(result='A91_INDEPENDENT_EXPECTED_PASS',shapes=shapes,outputs=rows),indent=2))
