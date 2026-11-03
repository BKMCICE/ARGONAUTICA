"""Validate the optional crt0 stack write-watermark snapshot, not a WC bound."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROW = re.compile(
    r'^STACK_PROBE start=0x([0-9a-f]{8}) top=0x([0-9a-f]{8}) '
    r'static_end=0x([0-9a-f]{8}) lowest_changed=0x([0-9a-f]{8}) '
    r'touched_bytes=(\d+) guard_bytes=(\d+) guard_changed_words=(\d+) '
    r'snapshot_sp=0x([0-9a-f]{8}) main_return=0x([0-9a-f]{8}) guard=(PASS|FAIL)$')

def require(condition, message):
    if not condition:
        raise ValueError(message)

def parse(raw, window_bytes=65536, guard_bytes=256, stack_top=None,
          static_end=None, expect_guard_failure=False, tcm_stack=False):
    lines=raw.decode('ascii').replace('\r','').splitlines()
    rows=[line for line in lines if line.startswith('STACK_PROBE')]
    require(len(rows)==1,'Expected exactly one completed STACK_PROBE snapshot')
    match=ROW.fullmatch(rows[0])
    require(match is not None,'Malformed stack snapshot')
    values=match.groups()
    start,top,end,lowest=(int(v,16) for v in values[:4])
    touched,guard,changed=(int(v) for v in values[4:7])
    sp,code=(int(v,16) for v in values[7:9])
    status=values[9]
    require(window_bytes>=512 and window_bytes%16==0,'Invalid window size')
    require(16<=guard_bytes<window_bytes and guard_bytes%4==0,'Invalid guard size')
    require(top-start==window_bytes and start%16==0 and top%16==0,'Window/ELF range mismatch')
    if tcm_stack:
        require(0xe000<=start<top==0x10000,'Window exceeds reserved TCM stack')
        require(0x80000000<=end<0x81000000,'TCM stack static data must remain DDR')
    else:
        require(end<=start,'Painted window overlaps static data')
    require(start<=lowest<=top and lowest%4==0,'Invalid changed-word address')
    require(touched==top-lowest,'Watermark arithmetic mismatch')
    require(guard==guard_bytes and 0<=changed<=guard//4,'Guard size/count mismatch')
    require((lowest<start+guard)==(changed>0),'Guard count contradicts lowest address')
    require((status=='FAIL')==(changed>0),'Guard status/count mismatch')
    require((changed>0)==expect_guard_failure,'Unexpected guard result')
    require(sp==top,'Main did not return with its original stack pointer')
    require(code==0,'Application returned an error')
    if stack_top is not None:
        require(top==stack_top,'Snapshot does not match linked stack top')
    if static_end is not None:
        require(end==static_end,'Snapshot does not match linked static end')
    return dict(result='EXPECTED_GUARD_CORRUPTION_PASS' if expect_guard_failure else 'STACK_WRITE_WATERMARK_PASS',
                window_start=f'{start:08x}',stack_top=f'{top:08x}',static_end=f'{end:08x}',
                lowest_changed=f'{lowest:08x}',window_bytes=window_bytes,touched_bytes=touched,
                guard_bytes=guard,guard_changed_words=changed,guard=status,
                unpainted_static_to_window_gap_bytes=None if tcm_stack else start-end,uart_sha256=hashlib.sha256(raw).hexdigest().upper(),
                scope='Write watermark through startup verification and main, sampled after main returns. '
                      'Excludes report function; does not measure reserved-but-unwritten stack or bound other paths, '
                      'canary collisions/restoration, future allocations, or worst-case minimum SP. '
                      'Guard intact is only this snapshot, not proof no overflow ever occurred.')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('uart',type=Path)
    p.add_argument('--window-bytes',type=int,default=65536)
    p.add_argument('--guard-bytes',type=int,default=256)
    p.add_argument('--stack-top',type=lambda s:int(s,0))
    p.add_argument('--static-end',type=lambda s:int(s,0))
    p.add_argument('--expect-guard-failure',action='store_true')
    p.add_argument('--tcm-stack',action='store_true')
    p.add_argument('--output',type=Path)
    a=p.parse_args()
    result=parse(a.uart.read_bytes(),a.window_bytes,a.guard_bytes,a.stack_top,a.static_end,a.expect_guard_failure,a.tcm_stack)
    if a.output:
        a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__':
    main()
