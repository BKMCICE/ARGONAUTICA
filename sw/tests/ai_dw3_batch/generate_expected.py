"""Independent CHW/int64 style integer oracle; no RTL/driver packing shared."""
from pathlib import Path
import json,hashlib
short=[(5,17,2,1,1,1,0),(7,19,3,2,1,0,0),(8,20,4,1,1,1,0),(3,3,1,1,0,1,0),(1,1,2,1,1,1,0),(5,9,1,1,2,0,1),(10,18,8,1,1,1,0),(9,19,32,2,1,1,0)]
full=[(80,80,32,1,1,1,0),(160,160,8,1,1,1,0)]
def signed(v):return (v+128)%256-128
def q24(v,m):
    p=v*m;r=(abs(p)+8388608)//16777216
    return -r if p<0 else r
def expected(g):
    h,w,c,s,p,leaky,crop=g;oh=(h+2*p-3)//s+1-crop;ow=(w+2*p-3)//s+1-crop
    out=[]
    for ch in range(c):
        m=(-1 if ch&1 else 1)*(16384+ch*29);b=ch%17-8
        for y in range(oh):
            for x in range(ow):
                dot=0
                for ky in range(3):
                    for kx in range(3):
                        yy=y*s+ky-p;xx=x*s+kx-p
                        if 0<=yy<h and 0<=xx<w:dot+=signed((8+(ch*h+yy)*w+xx)*73+19)*signed((8+ch*9+ky*3+kx)*59+31)
                v=q24(dot,m)+b
                if leaky and v<0:v=q24(v,1677722)
                out.append(max(-127,min(127,v))&255)
    value=2166136261
    for v in out:value=((value^v)*16777619)&0xffffffff
    return value
if __name__=='__main__':
    values=[[expected(g) for g in gs] for gs in (short,full)]
    path=Path(__file__).with_name('expected.h')
    text='/* Independent generate_expected.py, reproducible integer oracle. */\nstatic const uint32_t a53_expected[2][8]={\n'+',\n'.join(' {'+','.join(f'0x{v:08x}u' for v in row)+'}' for row in values)+'\n};\n'
    path.write_text(text,encoding='ascii',newline='\n');print(json.dumps(dict(values=values,sha256=hashlib.sha256(path.read_bytes()).hexdigest().upper())))
