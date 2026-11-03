"""Derive A74 from pinned current production; change only the packing call."""
from pathlib import Path
import argparse,hashlib
r=Path(__file__).resolve().parents[3];here=Path(__file__).resolve().parent
def generated():
    raw=(r/'sw/yolo_fixed/dw5x5_block.h').read_bytes().replace(b'\r\n',b'\n')
    assert hashlib.sha256(raw).hexdigest().upper()=='2D24CF8B4C34105D059539E829A072EC23FE0A277C52F819BF3EDCFF20E83E8C'
    text=raw.decode();fn=text[text.index('__attribute__((noinline))'):text.rindex('#endif')]
    assert fn.count('static int conv5x5_block(')==1 and fn.count('dw5_pack5(')==1
    candidate=fn.replace('static int conv5x5_block(','static int a74_fast(').replace('dw5_pack5(','a74_pack5(')
    assert candidate.replace('static int a74_fast(','static int conv5x5_block(').replace('a74_pack5(','dw5_pack5(')==fn
    return '/* A74 generated: exact current production, only packer call replaced. */\n'+candidate
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();path=here/'candidate.inc';text=generated()
    if a.check:assert path.read_text()==text
    else:path.write_text(text,encoding='ascii',newline='\n')
    print('A74_ONLY_PACKING_CALL_CHANGE_PROOF_PASS',hashlib.sha256(text.encode()).hexdigest().upper())
