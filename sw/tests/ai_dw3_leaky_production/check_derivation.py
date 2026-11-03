"""Prove exact bounded arithmetic and bind production to the A91 helper."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[3];w=a.out.resolve();assert w.drive.upper()=='F:';w.mkdir(parents=True,exist_ok=True)
sha=lambda b:hashlib.sha256(b).hexdigest().upper()
text=lambda q:q.read_bytes().replace(b'\r\n',b'\n').decode()
current=text(r/'sw/yolo_fixed/dw3x3_rolling.h')
previous=subprocess.check_output(['D:/Git/cmd/git.exe','show','e1e55ef760658b2f6b40f836323b5c55c9e547c5:sw/yolo_fixed/dw3x3_rolling.h'],cwd=r).replace(b'\r\n',b'\n').decode()
include='#if YOLO_DW3_LEAKY_CLIP\n#include "dw3_leaky_clip.h"\n#endif\n'
quant='#if YOLO_DW3_LEAKY_CLIP\n    return dw3_leaky_clip(v,leaky);\n#else\n    if(leaky&&v<0)v=apply_q24(v,YOLO_LEAKY_Q24);\n    return clip8(v);\n#endif'
assert current.count(include)==current.count(quant)==1
restored=current.replace(include,'').replace(quant,'    if(leaky&&v<0)v=apply_q24(v,YOLO_LEAKY_Q24);\n    return clip8(v);')
assert restored==previous,'Unexpected first-Q24/window/legacy driver change'
helper=text(r/'sw/yolo_fixed/dw3_leaky_clip.h');a91=text(r/'sw/tests/ai_dw3_leaky_clip/leaky_clip.h')
body=lambda t:re.sub(r'\s+','',t[t.index('int32_t v,uint32_t leaky)'):])
assert body(helper)==body(a91),'A91 exact helper body changed'
M=1677722;R=8388608;D=16777216;T=1265
q=lambda x:(x*M+R)//D
assert q(T-1)==126 and q(T)==127 and M>0
assert (T-1)*M+R==2129029216<2**31
for x in range(T):assert q(x)==((x*M+R)>>24)
assert helper.index('if(v<=-1265)')<helper.index('(uint32_t)(-v)')
mutants={'early_saturation':lambda v:-127 if v<=-1264 else -q(-v),'no_rounding':lambda v:-127 if v<=-T else -((-v*M)//D),'positive_sign':lambda v:-127 if v<=-T else q(-v)}
negative=[]
for name,fn in mutants.items():
 bad=next((v for v in range(-T,0) if fn(v)!=-min(q(-v),127)),None);assert bad is not None
 negative.append(dict(name=name,v=bad,expected=-min(q(-bad),127),mutated=fn(bad)))
out=dict(result='A92_EXACT_A91_DERIVATION_AND_ALL_INT32_ACTIVATION_PROOF_PASS',previous_commit='e1e55ef760658b2f6b40f836323b5c55c9e547c5',previous_rolling_sha256=sha(previous.encode()),production_rolling_sha256=sha(current.encode()),production_helper_sha256=sha((r/'sw/yolo_fixed/dw3_leaky_clip.h').read_bytes()),a91_helper_sha256=sha((r/'sw/tests/ai_dw3_leaky_clip/leaky_clip.h').read_bytes()),body_exactly_equal=True,first_q24_bias_and_all_window_driver_code_unchanged=True,small_interval_exhaustive=T,small_max_product_plus_half=(T-1)*M+R,threshold=T,at1264=q(T-1),at1265=q(T),negative_checks=negative,scope='All int32 activation v: magnitudes >=1265 saturate by positive-multiplier monotonicity, including INT_MIN before negation; remaining finite interval exhaustive. Nonnegative/nonleaky clip unchanged. Not a proof for arbitrary preceding first-Q24/bias overflow inputs; existing fixed-model contract remains.')
(w/'derivation_proof.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8');print(out['result'])
