"""Independent CHW integer reference, not shared with the packing driver."""
from pathlib import Path
import hashlib,json
short=[(3,9,120,1,2,1,0),(5,17,3,1,2,1,0),(7,19,3,2,2,0,0),(1,1,2,1,2,1,0),(3,3,2,1,4,0,1),(8,10,4,1,0,1,0),(3,8,1,1,2,0,0),(2,7,2,3,2,1,0)]
full=[(20,20,120,1,2,1,0),(10,10,96,1,2,1,0)]
def signed(v):return (v+128)%256-128
def q24(v,m):
    p=v*m;n=(abs(p)+8388608)//16777216
    return -n if p<0 else n
def expected(g):
    h,w,c,s,pad,leaky,crop=g;oh=(h+2*pad-5)//s+1-crop;ow=(w+2*pad-5)//s+1-crop;value=2166136261
    for ch in range(c):
        m=(-1 if ch&1 else 1)*(16384+ch*29);b=ch%17-8
        for y in range(oh):
            for x in range(ow):
                dot=0
                for ky in range(5):
                    for kx in range(5):
                        yy=y*s+ky-pad;xx=x*s+kx-pad
                        if 0<=yy<h and 0<=xx<w:dot+=signed((8+(ch*h+yy)*w+xx)*73+19)*signed((8+ch*25+ky*5+kx)*59+31)
                v=q24(dot,m)+b
                if leaky and v<0:v=q24(v,1677722)
                value=((value^(max(-127,min(127,v))&255))*16777619)&0xffffffff
    return value
if __name__=='__main__':
    values=[[expected(g) for g in gs] for gs in [short,full]]
    text='/* Independent generate_expected.py integer oracle. */\nstatic const uint32_t a74_expected[2][8]={\n'+',\n'.join(' {'+','.join(f'0x{v:08x}u' for v in row)+'}' for row in values)+'\n};\n'
    path=Path(__file__).with_name('expected.h');path.write_text(text,encoding='ascii',newline='\n');print('A74_ORACLE',values,hashlib.sha256(path.read_bytes()).hexdigest().upper())
