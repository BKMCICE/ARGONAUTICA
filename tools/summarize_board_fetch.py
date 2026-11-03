"""Check six warm TCM/DDR execution samples and compare their measured CPI."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def parse_samples(raw):
    if b'FETCH_LATENCY_PASS' not in raw or any(word in raw for word in (b'[TRAP]', b'FETCH_LATENCY_FAIL')):
        raise ValueError('Incomplete or failed fetch diagnostic')
    rows = []
    for line in raw.splitlines():
        if not line.startswith(b'FETCH_SAMPLE '):
            continue
        fields = dict(re.findall(rb'(\w+)=(\w+)', line))
        row = {key.decode(): value.decode() if key == b'location' else int(value)
               for key, value in fields.items()}
        expected = 34 * row['iterations'] + 1
        if not (row['traps'] == 0 and 0 < row['ticks'] <= row['cycles'] and
                expected <= row['instr'] < expected + 1000 and
                row['istall'] <= row['cycles'] and row['dstall'] <= row['cycles']):
            raise ValueError(f'Inconsistent sample: {row}')
        row['cpi'] = row['cycles'] / row['instr']
        if row['ihit'] + row['imiss']:
            row['i_cache_hit_rate'] = row['ihit'] / (row['ihit'] + row['imiss'])
        rows.append(row)
    if len(rows) != 6 or {(r['location'], r['trial']) for r in rows} != {
            (location, trial) for location in ('tcm', 'ddr') for trial in (1, 2, 3)}:
        raise ValueError('Require exactly three paired TCM/DDR samples')
    pairs = []
    for trial in (1, 2, 3):
        tcm = next(r for r in rows if r['location'] == 'tcm' and r['trial'] == trial)
        ddr = next(r for r in rows if r['location'] == 'ddr' and r['trial'] == trial)
        if (tcm['iterations'], tcm['instr']) != (ddr['iterations'], ddr['instr']):
            raise ValueError('Compared paths must execute the same number of instructions')
        pairs.append(dict(trial=trial, ddr_to_tcm_cycle_ratio=ddr['cycles'] / tcm['cycles']))
    return rows, pairs


def summarize(stage):
    raw = (stage / 'uart.log').read_bytes()
    meta = json.loads((stage / 'result.json').read_text(encoding='utf-8-sig'))
    if meta['result'] != 'PASS' or b'The done bit is 1' not in (stage / 'program.log').read_bytes():
        raise ValueError('Board download/run failed')
    rows, pairs = parse_samples(raw)
    return dict(result='PASS', stage=stage.name, bitstream_sha256=meta['sha256'],
                functional_source_commit=meta['source_commit'], image_sha256=meta['image_sha256'],
                image_source_commit=meta.get('image_source_commit'),
                uart_sha256=hashlib.sha256(raw).hexdigest().upper(), runs=rows, pairs=pairs,
                scope='Warm code path throughput including branches and call/control boundaries; not physical DDR access latency')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = summarize(args.stage)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
