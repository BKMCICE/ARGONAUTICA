"""Synthetic log validation, never counted as new physical-board evidence."""
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from summarize_block_phases import COUNTS, CYCLES, PHASES, expected_shapes, summarize

GRAPH = ROOT / 'sw/yolo_fixed/model_graph.h'


def fixture():
    raw = (ROOT / 'docs/validation/20261018-a05-block-profile/board/01_profile_run1/uart.log').read_bytes()
    rows = []
    for shape in expected_shapes(GRAPH.read_text()).values():
        v = dict(shape['expected'])
        n = v['samples']
        v.update(polls=n, setup=n * 10, pack=v['vectors'] * 20,
                 write=v['vectors'] * 12, wait=v['dots'] * 3 + n * 10,
                 read=v['rwords'] * 10, q24=v['rwords'] * 20,
                 weight=v['batches'] * 10, engine=v['dots'] * 3)
        v['task'] = sum(v[k] for k in PHASES) + n * 100
        v['max_task'] = math.ceil(v['task'] / n) + 1000
        rows.append('YOLO_BLOCK_PHASE ' + ' '.join(f'{k}={v[k]}' for k in COUNTS)
                    + ''.join(f' {k}=0x{v[k]:016x}' for k in CYCLES))
    return raw + ('\nYOLO_BLOCK_PHASE_BEGIN stride=64 tail=group_last clock_bits=32 calibration_min=2 calibration_max=4\n'
                  + '\n'.join(rows) + '\nYOLO_BLOCK_PHASE_END\n').encode()


class PhaseValidation(unittest.TestCase):
    def test_exact_shape_counts_and_tails(self):
        p = expected_shapes(GRAPH.read_text())
        self.assertEqual(len(p), 55)
        a, b = p[9]['expected'], p[129]['expected']
        self.assertEqual((a['tasks'], a['samples'], a['batches'], a['wwords'], a['vectors'], a['rwords']),
                         (19200, 301, 6, 72, 2408, 9632))
        self.assertEqual((b['tasks'], b['samples'], b['batches'], b['wwords'], b['vectors'], b['rwords'], b['dots']),
                         (3840, 61, 64, 10710, 5656, 1612, 22568))

    def test_valid_complete_log(self):
        out = summarize(fixture(), GRAPH)
        self.assertEqual(out['result'], 'YOLO_BLOCK_PHASE_PROFILE_PASS')
        self.assertEqual(len(out['layers']), 55)

    def reject(self, raw):
        with self.assertRaises(ValueError):
            summarize(raw, GRAPH)

    def test_reject_wrong_sampling_stride(self):
        self.reject(fixture().replace(b'stride=64 tail=', b'stride=32 tail='))

    def test_reject_missing_tail_policy(self):
        self.reject(fixture().replace(b'tail=group_last', b'tail=none'))

    def test_reject_bad_calibration(self):
        self.reject(fixture().replace(b'calibration_min=2', b'calibration_min=0'))

    def test_reject_repeated_envelope(self):
        self.reject(fixture() + b'YOLO_BLOCK_PHASE_END\n')

    def test_reject_missing_row(self):
        raw = fixture().splitlines(keepends=True)
        self.reject(b''.join(x for x in raw if not x.startswith(b'YOLO_BLOCK_PHASE index=9 ')))

    def test_reject_wrong_tail_result_count(self):
        self.reject(fixture().replace(b'rwords=1612 ', b'rwords=1613 '))

    def test_reject_wrong_hardware_cycles(self):
        import re
        self.reject(re.sub(rb' engine=0x([0-9a-f]{16})',
                           lambda m: f' engine=0x{int(m[1], 16) + 1:016x}'.encode(),
                           fixture(), count=1))

    def test_reject_zero_polls(self):
        import re
        self.reject(re.sub(rb'polls=\d+', b'polls=0', fixture(), count=1))

    def test_reject_phase_sum_exceeds_task(self):
        import re
        self.reject(re.sub(rb' task=0x[0-9a-f]{16}', b' task=0x0000000000000001', fixture(), count=1))

    def test_reject_extra_row_outside_envelope(self):
        raw = fixture()
        row = next(x for x in raw.splitlines() if x.startswith(b'YOLO_BLOCK_PHASE index='))
        self.reject(raw + row + b'\n')

    def test_reject_corrupted_detection(self):
        self.reject(fixture().replace(b'car 844/1000', b'car 843/1000'))


if __name__ == '__main__':
    unittest.main()
