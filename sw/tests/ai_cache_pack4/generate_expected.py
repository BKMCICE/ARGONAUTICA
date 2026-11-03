"""Independent signed CHW/int64/division Q24 oracle; synthetic fixed data."""
from pathlib import Path
import argparse,hashlib,json,numpy as np
here=Path(__file__).resolve().parent
full=[(160,160,4,24,1,1,0),(160,160,8,8,1,1,0),(40,40,16,96,1,1,0),(20,20,120,120,1,1,0),(10,10,120,96,1,1,0),(10,10,120,96,1,1,1),(3,17,17,9,2,2,0),(160,160,8,4,1,1,0)]
short=[(2,9,4,24,1,1,0),(2,9,8,8,1,1,0),(2,9,16,16,1,1,0),(1,9,17,9,1,1,0),(2,10,10,9,1,1,0),(2,10,10,9,1,1,1),(3,17,17,9,2,2,0),(2,9,8,4,1,1,0)]
def scale(a,m):
 p=a*m;rounded=(np.abs(p)+8388608)//16777216;return np.where(p<0,-rounded,rounded)
def expected(shape):
 h,w,ci,co,g,s,align=shape;oc=co*g;oh=(h-1)//s+1;ow=(w-1)//s+1
 x=(((np.arange(ci*g*h*w,dtype=np.int64)+8)*73+19+128)%256-128).reshape(g,ci,h*w)
 k=(((np.arange(oc*ci,dtype=np.int64)+8)*59+31+128)%256-128).reshape(g,co,ci)
 pos=np.array([y*s*w+xx*s for y in range(oh) for xx in range(ow)])
 dot=np.concatenate([k[i]@x[i][:,pos] for i in range(g)],axis=0)
 ch=np.arange(oc,dtype=np.int64);mult=np.where(ch&1,-1,1)*(16384+ch*29);bias=ch%17-8
 v=scale(dot,mult[:,None])+bias[:,None];v=np.where(v<0,scale(v,1677722),v)
 raw=np.clip(v,-127,127).astype(np.int8).tobytes();fnv=2166136261
 for b in raw:fnv=((fnv^b)*16777619)&0xffffffff
 return dict(shape=list(shape),output_bytes=len(raw),fnv1a=f'{fnv:08x}',output_sha256=hashlib.sha256(raw).hexdigest().upper())
def generated():
 rows=[[expected(s) for s in group] for group in [short,full]]
 header='/* Independent generate_expected.py signed CHW oracle. */\nstatic const uint32_t a82_expected[2][8]={\n'+',\n'.join(' {'+','.join('0x'+x['fnv1a']+'u' for x in group)+'}' for group in rows)+'\n};\n'
 geometry='/* h,w,input channels/group,output channels/group,groups,stride,output offset. */\nstatic const uint32_t a82_geometries[2][8][7]={\n'+',\n'.join('{'+','.join('{'+','.join(map(str,shape))+'}' for shape in group)+'}' for group in [short,full])+'\n};\n'
 return rows,header,geometry
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--out',type=Path);a=p.parse_args();rows,header,geometry=generated()
 for name,text in [('expected.h',header),('geometry.h',geometry)]:
  if a.check:assert (here/name).read_text()==text
  else:(here/name).write_text(text,encoding='ascii',newline='\n')
 if a.out:a.out.write_text(json.dumps(dict(result='A82_INDEPENDENT_CHW_EXPECTED',short=rows[0],full=rows[1]),indent=2)+'\n')
 print('A82_INDEPENDENT_EXPECTED_PASS')
