"""Regress repeated predicted calls/returns between boot TCM and cached DDR."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def bnez(register, offset):
    value = offset & 0x1fff
    return ((value >> 12) << 31 | ((value >> 5) & 63) << 25 |
            register << 15 | 1 << 12 | ((value >> 1) & 15) << 8 |
            ((value >> 11) & 1) << 7 | 0x63)


def program(target):
    # 64 calls through the SAME JALR, training predictions in both domains.
    # Callee increments s0. Wrong return count produces a failing tohost.
    return [((target + 0x800) & 0xfffff000) | 0x2b7,
            (target & 0xfff) << 20 | 5 << 15 | 5 << 7 | 0x13,
            0x04000593, 0x00000413, 0x000280e7, 0xfff58593,
            bnez(11, -8), 0x04044413, 0x00141413, 0x00146413,
            0x0000f337, 0x00832023, 0x0000006f]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', required=True, type=Path)
    args = parser.parse_args()
    work = args.build_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    rows = []
    for caller in ('tcm', 'ddr'):
        tcm = [0x13] * 16384
        ddr = [0] * 16384
        callee = [0x00140413, 0x00008067]  # ADDI s0,s0,1; RET
        if caller == 'tcm':
            code = program(0x80000000)
            tcm[:len(code)] = code
            ddr[:len(callee)] = callee
        else:
            tcm[:2] = [0x800002b7, 0x00028067]  # boot jump to DDR
            tcm[0x1000 // 4:0x1000 // 4 + len(callee)] = callee
            code = program(0x1000)
            ddr[:len(code)] = code
        tcm_path = work / f'{caller}_caller.hex'
        ddr_path = work / f'{caller}_caller.linehex'
        tcm_path.write_text(''.join(f'{word:08x}\n' for word in tcm), encoding='ascii')
        ddr_path.write_text(''.join(''.join(f'{word:08x}' for word in reversed(ddr[i:i+8])) + '\n'
                                    for i in range(0, len(ddr), 8)), encoding='ascii')
        for btb in (False, True):
            name = f'{caller}_caller_btb{int(btb)}'
            log = work / f'{name}.log'
            cmd = [sys.executable, '-X', 'utf8', '-B', str(ROOT / 'tools/run_soc_ddr.py'),
                   str(tcm_path), '--ddr-hex', str(ddr_path), '--timeout', '20000',
                   '--build-dir', str(work / name), '--log', str(log)]
            if not btb:
                cmd.append('--no-btb')
            run = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                                 encoding='utf-8', errors='replace')
            text = log.read_text(encoding='utf-8') if log.exists() else run.stdout + run.stderr
            passed = run.returncode == 0 and 'DDR_SOC_PASS' in text
            rows.append(dict(case=name, calls=64, result='PASS' if passed else 'FAIL',
                             exit_code=run.returncode))
            print(name, rows[-1]['result'], text.strip(), flush=True)
    result = dict(result='PASS' if all(row['result'] == 'PASS' for row in rows) else 'FAIL', cases=rows)
    (work / 'summary.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return 0 if result['result'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
