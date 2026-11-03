from pathlib import Path
import argparse,hashlib,json
t=Path(__file__).resolve().parent;r=t.parents[2];s=(r/'sw/yolo_fixed/dw5x5_block.h').read_text();spec=json.loads((t/'change.json').read_text())
assert hashlib.sha256(s.encode()).hexdigest().upper()==spec['header_sha256_normalized']
fn=s[s.index('__attribute__((noinline))'):s.index('#undef DW5_PACK_INPUT')]
assert fn.count(spec['old_store'])==1
placebo=fn.replace('static int conv5x5_block(','static int a88_placebo_block(')
candidate=fn.replace('static int conv5x5_block(','static int a88_candidate_block(').replace(spec['old_store'],spec['new_store'])
assert placebo.replace('static int a88_placebo_block(','static int conv5x5_block(')==fn
assert candidate.replace('static int a88_candidate_block(','static int conv5x5_block(').replace(spec['new_store'],spec['old_store'])==fn
body=placebo+'\n'+candidate
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
if a.check:assert (t/'candidate.inc').read_text()==body
else:(t/'candidate.inc').write_text(body,encoding='utf-8',newline='\n')
print('A88_ONLY_WRITEBACK_NAMESPACE_CHANGE_PASS',hashlib.sha256(body.encode()).hexdigest().upper())
