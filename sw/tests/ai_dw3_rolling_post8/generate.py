"""Pin production validation and derive a namespace-only full rolling control."""
from pathlib import Path
import argparse,hashlib,json
t=Path(__file__).resolve().parent;r=t.parents[2]
s=(r/'sw/yolo_fixed/dw3x3_rolling.h').read_text()
expected='A5950A1B04B65402F37E50A4F3634C7F6736FA1D43035A13DCCB305C55EE7B83'
assert hashlib.sha256(s.encode()).hexdigest().upper()==expected
fn=s[s.index('__attribute__((noinline))'):s.rindex('#endif')]
validation=fn[:fn.index('#ifdef YOLO_HOST_TEST')]
body=(t/'candidate_body.inc').read_text();marker='/* A89_VALIDATED_FUNCTION_BEGIN */'
assert body.count(marker)==1
candidate=body.replace(marker,validation.replace('static int conv3x3_rolling(','static int a89_post8_rolling('))
placebo=fn.replace('static int conv3x3_rolling(','static int a89_placebo_rolling(')
assert placebo.replace('static int a89_placebo_rolling(','static int conv3x3_rolling(')==fn
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
for name,text in [('candidate_rolling.h',candidate),('placebo_rolling.h',placebo)]:
 if a.check:assert (t/name).read_text()==text
 else:(t/name).write_text(text,encoding='utf-8',newline='\n')
print('A89_PINNED_ORIGINAL_VALIDATOR_AND_NAMESPACE_CONTROL_PASS',expected)
