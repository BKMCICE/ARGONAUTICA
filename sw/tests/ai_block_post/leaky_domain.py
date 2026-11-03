"""Prove the dedicated unsigned leaky path with final clip[-127,127]."""
from pathlib import Path
import argparse,json,hashlib
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();w=a.output;w.mkdir(parents=True,exist_ok=True)
M=1677722;R=8388608;D=16777216;T=1265
q=lambda x:(x*M+R)//D
assert q(T-1)==126 and q(T)==127 and (T-1)*M+R<2**31
# q is nondecreasing for x>=0 since M>0. Thus all x>=T clip to127.
# Below T the 11-bit magnitude and 32-bit unsigned product/round are exact.
for x in range(T):assert q(x)==((x*M)>>24)+(((x*M)>>23)&1)
lines=[]
for x in range(2049):
    value=-min(q(x),127)
    bits=((-x&0xffffffff)<<104)|(D<<72)|(1<<39)|(value&255)
    lines.append(f'{bits:034x}\n')
# Bias can legally produce INT_MIN after a zero Q24; pre-saturation avoids abs.
bits=(0x80000000<<40)|(1<<39)|0x81;lines.append(f'{bits:034x}\n')
raw=''.join(lines).encode('ascii');(w/'leaky_vectors.hex').write_bytes(raw)
out=dict(result='A32_UNSIGNED_LEAKY_DOMAIN_PASS',threshold=T,constant=M,at_threshold=q(T),below_threshold=q(T-1),max_small_product=(T-1)*M,max_small_with_round=(T-1)*M+R,vectors=len(lines),vector_sha256=hashlib.sha256(raw).hexdigest().upper(),proof='For any biased int32 v<0, x=-v is mathematically 1..2^31. Positive M makes Q(x) monotone; Q(1265)=127 so x>=1265 clips to127. For x<1265 unsigned11 magnitude, unsigned32 product and upper-byte plus bit23 reproduce the original division Q24 exactly. Return negative byte without a signed multiplier feedback mux. INT_MIN saturates before magnitude formation; first Q24/bias validation remains unchanged.')
(w/'leaky_domain.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8');print(out['result'],out['vectors'])
