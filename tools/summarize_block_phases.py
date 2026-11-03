"""Validate deterministic sampled 1x1 block-task windows, not unprofiled speed."""
import argparse
import hashlib
import json
import re
from pathlib import Path

from summarize_yolo_layers import read_graph, summarize as summarize_layers

PHASES = ('setup', 'pack', 'write', 'wait', 'read', 'q24')
COUNTS = ('index', 'tasks', 'samples', 'batches', 'wwords', 'vectors', 'iwords',
          'rwords', 'polls', 'dots', 'max_task')
CYCLES = ('weight',) + PHASES + ('task', 'engine')


def require(value, message):
    if not value:
        raise ValueError(message)


def expected_shapes(text):
    rows = {}
    for line in text.splitlines():
        found = re.search(r'/\* layer (\d+) \*/', line)
        if not found:
            continue
        v = [int(x) for x in re.findall(r'-?\d+', line.split('/*')[0])]
        require(len(v) == 25, 'Invalid full graph row')
        kind, ih, iw, ic, oh, ow, oc, size, stride, groups, pad = v[:11]
        if kind != 1 or size != 1:
            continue
        require(groups > 0 and ic % groups == oc % groups == 0, 'Invalid groups')
        ci, co = ic // groups, oc // groups
        require(0 < ci <= 224 and co > 0 and pad == 0 and min(ih, iw, oh, ow, stride) > 0, 'Unsupported block shape')
        blocks = (ci + 8) // 9
        e = dict(index=int(found[1]), tasks=0, samples=0, batches=0, wwords=0,
                 vectors=0, iwords=0, rwords=0, dots=0)
        for _ in range(groups):
            for base in range(0, co, 4):
                outputs = min(4, co - base)
                e['batches'] += 1
                e['wwords'] += outputs * blocks * 3
                for y in range(oh):
                    for x in range(0, ow, 8):
                        pixels = min(8, ow - x)
                        take = e['tasks'] % 64 == 0 or (y + 1 == oh and x + pixels == ow and base + outputs == co)
                        e['tasks'] += 1
                        if take:
                            e['samples'] += 1
                            e['vectors'] += blocks * pixels
                            e['iwords'] += blocks * pixels * 3
                            e['rwords'] += outputs * pixels
                            e['dots'] += blocks * outputs * pixels
        rows[e['index']] = dict(expected=e, input_channels=ci,
                              output_channels=co, blocks=blocks, groups=groups)
    return rows


def summarize(raw, graph_path):
    graph, graph_sha = read_graph(graph_path)
    layer_report = summarize_layers(raw, graph, 100000000)
    expected = expected_shapes(graph_path.read_text(encoding='utf-8-sig'))
    lines = raw.decode('ascii').replace('\r', '').splitlines()
    header = [s for s in lines if s.startswith('YOLO_BLOCK_PHASE_BEGIN')]
    require(len(header) == 1 and lines.count('YOLO_BLOCK_PHASE_END') == 1, 'Missing/repeated phase envelope')
    h = re.fullmatch(r'YOLO_BLOCK_PHASE_BEGIN stride=64 tail=group_last clock_bits=32 calibration_min=(\d+) calibration_max=(\d+)', header[0])
    require(h, 'Bad phase header')
    low, high = map(int, h.groups())
    require(0 < low <= high < 1000000, 'Invalid CSR calibration')
    begin, end = lines.index(header[0]), lines.index('YOLO_BLOCK_PHASE_END')
    require(begin < end, 'Reversed phase envelope')
    rows = []
    pattern = 'YOLO_BLOCK_PHASE ' + ' '.join(k + r'=(\d+)' for k in COUNTS)
    pattern += ''.join(' ' + k + r'=0x([0-9a-f]{16})' for k in CYCLES)
    records = [s for s in lines if s.startswith('YOLO_BLOCK_PHASE ')]
    require(len(records) == len(expected) and all(s.startswith('YOLO_BLOCK_PHASE ') for s in lines[begin + 1:end]), 'Invalid phase rows/envelope')
    for line in records:
        match = re.fullmatch(pattern, line)
        require(match, 'Malformed phase row')
        values = match.groups()
        row = dict(zip(COUNTS, map(int, values[:len(COUNTS)])))
        row.update(zip(CYCLES, (int(x, 16) for x in values[len(COUNTS):])))
        require(row['index'] in expected and row['index'] not in [x['index'] for x in rows], 'Unexpected/repeated layer')
        shape = expected[row['index']]
        require(all(row[k] == v for k, v in shape['expected'].items()), 'Shape/sampling/transfer/dot count mismatch')
        require(row['samples'] <= row['polls'] <= row['samples'] * 100000, 'Poll count outside bounded loop')
        # A02 FSM has exactly LOAD/MULT/ADD per nine-lane dot; no DMA.
        require(row['engine'] == row['dots'] * 3, 'Hardware cycle/dot counters disagree with A02 FSM')
        require(row['engine'] <= row['wait'], 'Engine cycles exceed submit/wait windows')
        require(0 < row['max_task'] < 2**31 and 0 < row['task'] <= row['max_task'] * row['samples'], 'Invalid sampled task interval')
        require(all(row[k] > 0 for k in CYCLES), 'Empty timing window')
        phases = sum(row[k] for k in PHASES)
        require(phases <= row['task'], 'Overlapping/excess phase windows')
        require(row['task'] + row['weight'] < layer_report['layers'][row['index']]['cycles'], 'Task windows exceed layer window')
        row.update(input_channels=shape['input_channels'], output_channels=shape['output_channels'],
                   remainder_cycles=row['task'] - phases,
                   phase_percent_of_sampled_task={k: row[k] / row['task'] * 100 for k in PHASES},
                   timing_windows=row['batches'] + 4 * row['samples'] + 2 * row['vectors'])
        rows.append(row)
    require([x['index'] for x in rows] == sorted(expected), 'Phase rows out of graph order')
    return dict(result='YOLO_BLOCK_PHASE_PROFILE_PASS', nominal_hz=100000000,
                graph_sha256=graph_sha, uart_sha256=hashlib.sha256(raw).hexdigest().upper(),
                forward_cycles=layer_report['forward_cycles'], calibration_min=low, calibration_max=high,
                sample_stride=64, tail_policy='last task of each input group', layers=rows,
                scope='Raw deterministic sampled windows with barriers and instrumentation/layout overhead; includes first/every64th and group-last task. Not random sampling, unbiased full-layer attribution, independent DDR stalls, DMA gain, or a new formal speed. Hardware engine cycles overlap submit/wait and must not be added twice. CSR-low intervals assume each task <2^32 cycles; observed max reported, not a universal timeout proof.')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('uart', type=Path)
    p.add_argument('--graph', type=Path, default=Path('sw/yolo_fixed/model_graph.h'))
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    out = summarize(args.uart.read_bytes(), args.graph)
    args.output.write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8')
    print(out['result'], len(out['layers']), 'layers')


if __name__ == '__main__':
    main()
