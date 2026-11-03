"""Validate board CoreMark logs and summarize version-bound baseline/profile runs."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def summarize(stages, profile=False):
    rows = []
    bindings = set()
    for stage in stages:
        raw = (stage / 'uart.log').read_bytes()
        meta = json.loads((stage / 'result.json').read_text(encoding='utf-8-sig'))
        require(meta['result'] == 'PASS' and meta['program_exit'] == 0, f'{stage}: board stage failed')
        program = (stage / 'program.log').read_bytes()
        require(b'The done bit is 1' in program, f'{stage}: missing FPGA DONE')
        require(b'GO\r' in raw and b'Correct operation validated' in raw, f'{stage}: incomplete run')
        require(not any(s in raw for s in (b'[TRAP]', b'Errors detected', b'BAD HASH', b'HASH FAIL')),
                f'{stage}: firmware error')
        for key, value in ((b'seedcrc', b'e9f5'), (b'crclist', b'e714'),
                           (b'crcmatrix', b'1fd7'), (b'crcstate', b'8e3a'), (b'crcfinal', b'4983')):
            require(re.search(key + rb'\s*:\s*0x' + value + rb'\b', raw), f'{stage}: {key} mismatch')
        ticks = int(re.search(rb'Total ticks\s*:\s*(\d+)', raw)[1])
        iterations = int(re.search(rb'Iterations\s*:\s*(\d+)', raw)[1])
        require(iterations == 2000, f'{stage}: expected 2000 iterations')
        hz = meta['cpu_hz_nominal']
        seconds = ticks / hz
        observed = meta['events']['coremark_validated'] - meta['events']['go_received']
        require(10 <= seconds < 2**32 / hz and abs(observed - seconds) < 2,
                f'{stage}: invalid duration or likely 32-bit timer wrap')
        row = dict(stage=stage.name, ticks=ticks, iterations=iterations,
                   seconds_at_nominal_clock=seconds, uart_observed_seconds=observed,
                   coremark_at_nominal_clock=iterations / seconds,
                   coremark_per_mhz=iterations * 1e6 / ticks,
                   uart_sha256=hashlib.sha256(raw).hexdigest().upper(), result='PASS')
        bindings.add((meta['sha256'], meta['image_sha256'], hz, meta['source_commit'],
                      meta.get('image_source_commit')))
        if profile:
            require(raw.count(b'COREMARK_PROFILE_BEGIN') == raw.count(b'COREMARK_PROFILE_END') == 1,
                    f'{stage}: missing or repeated profile block')
            block = raw.split(b'COREMARK_PROFILE_BEGIN', 1)[1].split(b'COREMARK_PROFILE_END', 1)[0]
            counts = {}
            for name in ('cycles', 'instr', 'branch', 'mispred', 'lduse', 'istall', 'dstall',
                         'traps', 'ihit', 'imiss', 'dhit', 'dmiss'):
                counts[name] = int(re.search(name.encode() + rb'=(\d+)\b', block)[1])
            delta = int(re.search(rb'cycle64_delta=0x([0-9a-fA-F]{16})\b', block)[1], 16)
            require(delta < 2**32 and ticks <= delta and delta - ticks < hz / 100,
                    f'{stage}: profile timer wrap or excessive boundary overhead')
            require(abs(counts['cycles'] - ticks) < hz / 100 and counts['traps'] == 0,
                    f'{stage}: counter interval mismatch or trap')
            require(0 < counts['instr'] <= counts['cycles'] and
                    0 < counts['branch'] <= counts['instr'] and counts['mispred'] <= counts['branch'],
                    f'{stage}: inconsistent instruction/branch counts')
            require(all(0 <= value <= counts['cycles'] for value in counts.values()),
                    f'{stage}: counter exceeds measured cycles')
            row['profile_counts'] = counts
            row['cycle64_delta'] = delta
            row['cpi'] = counts['cycles'] / counts['instr']
            row['branch_mispredict_rate'] = counts['mispred'] / counts['branch']
            for cache in ('i', 'd'):
                total = counts[cache + 'hit'] + counts[cache + 'miss']
                require(total > 0, f'{stage}: no {cache} cache events')
                row[cache + '_cache_hit_rate'] = counts[cache + 'hit'] / total
            row['stall_cycle_fractions_overlapping'] = {
                name: counts[name] / counts['cycles'] for name in ('lduse', 'istall', 'dstall')}
        else:
            require(b'COREMARK_PROFILE_BEGIN' not in raw, f'{stage}: profile passed as baseline')
        rows.append(row)
    require(len(bindings) == 1, 'Do not combine different bitstreams, images, clocks or source revisions')
    bit, image, hz, source, image_source = bindings.pop()
    return dict(result='PASS', mode='diagnostic_profile' if profile else 'baseline',
                bitstream_sha256=bit, image_sha256=image, functional_source_commit=source,
                image_source_commit=image_source, cpu_hz_nominal=hz,
                frequency_status='NOMINAL_ONLY_NOT_INDEPENDENTLY_MEASURED',
                runs=rows, coremark_mean=sum(r['coremark_at_nominal_clock'] for r in rows) / len(rows),
                coremark_per_mhz_mean=sum(r['coremark_per_mhz'] for r in rows) / len(rows),
                ticks_spread=max(r['ticks'] for r in rows) - min(r['ticks'] for r in rows))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stages', nargs='+', type=Path)
    parser.add_argument('--profile', action='store_true')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = summarize(args.stages, args.profile)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
