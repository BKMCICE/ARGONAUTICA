from pathlib import Path
import argparse,hashlib,json
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();s=Path(__file__).resolve().parent
def value(i,p):
 if p==0:
  v=(i*73+19)&255;return v-256 if v>=128 else v
 if p==1:return -1-((i*37+11)&127)
 if p==2:return -128
 return i%255-127
def quant(v):
 product=v*29567173;q=(abs(product)+8388608)//16777216
 if product<0:q=-q
 return max(-127,min(127,q))
rows=[];hashes=[]
for kernel in [3,5,9]:
 for pattern in range(4):
  row=[];pad=kernel//2
  for c in range(48):
   for y in range(10):
    for x in range(10):
     v=max([-127]+[value((c*10+yy)*10+xx,pattern) for yy in range(y-pad,y-pad+kernel) for xx in range(x-pad,x-pad+kernel) if 0<=yy<10 and 0<=xx<10]);row.append(quant(v))
  h=2166136261
  for v in row:h=((h^(v&255))*16777619)&0xffffffff
  rows.append(row);hashes.append(h)
text='/* Independent 2D/int64/division reference; no prototype import. */\n#ifndef A96_EXPECTED_H\n#define A96_EXPECTED_H\nstatic const int8_t expected_output[12][4800]={\n'+',\n'.join('{'+','.join(map(str,row))+'}' for row in rows)+'\n};\nstatic const uint32_t expected_fnv[12]={'+','.join(hex(h)+'u' for h in hashes)+'};\n#endif\n'
out=s/'expected.h'
if a.check:assert out.read_text()==text,'Stale oracle header'
else:out.write_text(text,encoding='utf-8',newline='\n')
print('A96_12_FULL_OUTPUT_ORACLES_PASS',hashlib.sha256(text.encode()).hexdigest().upper())
