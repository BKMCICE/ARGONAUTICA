from pathlib import Path
import argparse,hashlib
t=Path(__file__).resolve().parent;r=t.parents[2];base=r/'sw/tests/ai_dw3_rolling_post8/candidate_rolling.h'
s=base.read_text();assert hashlib.sha256(s.encode()).hexdigest().upper()=='5072A297550E84E014483CC2D0F4A3940CC5CFE08EA1BB233CFC19C289235867'
post=s.replace('a89_post8_rolling','a90_post_rolling').replace('a89_','a90_post_')
raw=s.replace('a89_post8_rolling','a90_raw_rolling').replace('a89_','a90_raw_')
lo=raw.index('__attribute__((noinline)) static int a90_raw_finish(');hi=raw.index('/* The validator prefix',lo)
raw=raw[:lo]+(t/'raw_finish.inc').read_text()+raw[hi:]
old='AI_BLOCK_WRITE(0x204u,1u|(l->leaky?2u:0u));';new='AI_BLOCK_WRITE(0x204u,0u);'
assert raw.count(old)==1;raw=raw.replace(old,new)
oldcall='a90_raw_finish(dest+ox,count)';newcall='a90_raw_finish(dest+ox,count,params+oc*2,l->leaky)'
assert raw.count(oldcall)==1;raw=raw.replace(oldcall,newcall)
# The complete layer loop is identical after backend namespace/mode/call canonicalization.
p_loop=post[post.index('__attribute__((noinline)) static int a90_post_rolling('):]
r_loop=raw[raw.index('__attribute__((noinline)) static int a90_raw_rolling('):]
assert r_loop.replace(new,old,1).replace(newcall,oldcall).replace('a90_raw_','a90_post_')==p_loop
a=argparse.ArgumentParser();a.add_argument('--check',action='store_true');args=a.parse_args()
for name,body in [('post_rolling.h',post),('raw_rolling.h',raw)]:
 if args.check:assert (t/name).read_text()==body
 else:(t/name).write_text(body,encoding='utf-8',newline='\n')
print('A90_SAME_SOURCE_BATCH_LOOP_AND_PINNED_A89_POST_PASS')
