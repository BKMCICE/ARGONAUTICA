from pathlib import Path
import argparse,hashlib
r=Path(__file__).resolve().parents[3];t=Path(__file__).resolve().parent
def generated():
 s=(r/'sw/yolo_fixed/main.c').read_text();lo=s.index('__attribute__((noinline)) static int conv1x1_block(');hi=s.index('\n}\n#endif\n\nstatic const int8_t *output_of',lo)+2;fn=s[lo:hi]+'\n'
 old='block_cache_pack(layer, group_input, plane, out_plane, in_group, blocks);';new='a82_cache_pack(layer, group_input, plane, out_plane, in_group, blocks);';assert fn.count(old)==1
 placebo=fn.replace('static int conv1x1_block(','static int a82_placebo_block(');candidate=fn.replace('static int conv1x1_block(','static int a82_candidate_block(').replace(old,new)
 assert placebo.replace('static int a82_placebo_block(','static int conv1x1_block(')==fn
 assert candidate.replace('static int a82_candidate_block(','static int conv1x1_block(').replace(new,old)==fn
 body=placebo+'\n'+candidate
 return body
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();body=generated()
 if a.check:assert (t/'candidate.inc').read_text()==body
 else:(t/'candidate.inc').write_text(body,encoding='utf-8',newline='\n')
 print('A82_ONLY_CACHE_CALL_NAMESPACE_CHANGE_PASS',hashlib.sha256(body.encode()).hexdigest().upper())
