"""Verify the saved public source snapshot; no compiler or hardware access."""
from pathlib import Path
import hashlib,json

ROOT=Path(__file__).resolve().parents[1]

def main():
    record=json.loads((ROOT/'PUBLIC_SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
    expected={x['path']:x for x in record['source_files']}
    actual={p.relative_to(ROOT).as_posix()for p in ROOT.rglob('*')if p.is_file()and '.git'not in p.relative_to(ROOT).parts}
    if actual!=set(expected)|{'PUBLIC_SOURCE_MANIFEST.json'}:
        raise ValueError('Source file set differs from the frozen manifest')
    for name,row in expected.items():
        path=ROOT/name
        if path.is_symlink()or not path.resolve().is_relative_to(ROOT):raise ValueError('Unexpected source link '+name)
        blob=path.read_bytes()
        if len(blob)!=row['bytes']or hashlib.sha256(blob).hexdigest().upper()!=row['sha256'].upper():
            raise ValueError('Saved source bytes differ: '+name)
    for name in ('models/yolo_fastest_1_1/LICENSE','third_party/coremark/LICENSE.md',
                 'third_party/riscv-tests/LICENSE','third_party/riscv-tests/env/LICENSE'):
        if name not in expected:raise ValueError('Required original third-party license missing '+name)
    if record['full_board_build_available']is not False or record['git_history_copied']is not False:
        raise ValueError('Public snapshot scope is incorrect')
    print(json.dumps(dict(result='PUBLIC_SOURCE_SAVED_BYTES_PASS_NOT_BOARD_ACCEPTANCE',
        checked_files=len(expected),missing_vendor_ip_files=len(record['missing_vendor_ip_files']),
        full_board_build_available=False,hardware_retested=False),ensure_ascii=False))

if __name__=='__main__':main()
