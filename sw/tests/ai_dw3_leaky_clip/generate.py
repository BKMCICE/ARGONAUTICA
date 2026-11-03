from pathlib import Path
import argparse,hashlib
t=Path(__file__).resolve().parent;r=t.parents[2];s=(r/'sw/yolo_fixed/dw3x3_rolling.h').read_text()
assert hashlib.sha256(s.encode()).hexdigest().upper()=='A5950A1B04B65402F37E50A4F3634C7F6736FA1D43035A13DCCB305C55EE7B83'
old='''    if(leaky&&v<0)v=apply_q24(v,YOLO_LEAKY_Q24);
    return clip8(v);'''
new='''    return a91_leaky_clip(v,leaky);'''
assert s.count(old)==1
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
for variant in ['placebo','candidate']:
 body=s.replace('YOLO_DW3X3_ROLLING_H','A91_'+variant.upper()+'_ROLLING_H').replace('conv3x3_rolling','a91_'+variant+'_rolling').replace('dw3_','a91_'+variant+'_dw3_').replace('"../common/ai_mac_block.h"','"../../common/ai_mac_block.h"')
 if variant=='candidate':body=body.replace(old,new)
 reverse=body.replace('A91_'+variant.upper()+'_ROLLING_H','YOLO_DW3X3_ROLLING_H').replace('a91_'+variant+'_rolling','conv3x3_rolling').replace('a91_'+variant+'_dw3_','dw3_').replace('"../../common/ai_mac_block.h"','"../common/ai_mac_block.h"')
 if variant=='candidate':reverse=reverse.replace(new,old)
 assert reverse==s
 if args.check:assert (t/f'{variant}_rolling.h').read_text()==body
 else:(t/f'{variant}_rolling.h').write_text(body,encoding='utf-8',newline='\n')
print('A91_ONLY_LEAKY_CLIP_PLUS_NAMESPACE_PROOF_PASS')
