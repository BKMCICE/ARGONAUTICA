"""Adversarial log fixtures; these tests do not claim physical-board execution."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from summarize_yolo_layers import EXPECTED_DETECTIONS, read_graph, summarize


class LayerProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.graph, _ = read_graph(Path(__file__).resolve().parents[2] / "sw/yolo_fixed/model_graph.h")

    def fixture(self):
        # The total deliberately exceeds 32 bits; all durations are synthetic.
        self.rows = [f"YOLO_LAYER index={r['index']} kind={r['kind']} kernel={r['kernel']} cycles=0x{100+r['index']:016x}"
                     for r in self.graph]
        return ("\n".join(["RV32BOOT1", "GO", "YOLO_FIXED START", "YOLO_INPUT 307200",
                           "YOLO_INPUT_OK", "YOLO_FIXED HEADS 99860b0f 98155281",
                           "YOLO_FIXED PASS", "detections=6", *EXPECTED_DETECTIONS,
                           "YOLO_FORWARD_CYCLES=0x0000000400000000",
                           "YOLO_PROFILE_BEGIN layers=131", *self.rows, "YOLO_PROFILE_END"]) + "\n").encode()

    def check_bad(self, raw):
        with self.assertRaises(ValueError):
            summarize(raw, self.graph, 100_000_000)

    def test_valid_64_bit_total_and_group_accounting(self):
        result = summarize(self.fixture(), self.graph, 100_000_000)
        self.assertEqual(result['forward_cycles'], 2**34)
        self.assertEqual(result['sampled_layer_cycles'], 21615)
        self.assertEqual(sum(v['cycles'] for v in result['groups'].values()), 21615)
        self.assertEqual(sum(v['layers'] for v in result['groups'].values()), 131)
        self.assertEqual(result['top_layers'][0]['index'], 130)
        self.assertEqual(result['layers'][2]['operator'], 'conv3x3_depthwise')
        self.assertEqual(sum(g['layers'] for k, g in result['groups'].items() if k.startswith('conv')), 84)

    def test_missing_layer(self):
        raw = self.fixture()
        self.check_bad(raw.replace((self.rows[8] + '\n').encode(), b''))

    def test_repeated_layer(self):
        raw = self.fixture()
        self.check_bad(raw.replace(self.rows[8].encode(), self.rows[7].encode()))

    def test_wrong_graph_type(self):
        self.check_bad(self.fixture().replace(b'index=0 kind=1', b'index=0 kind=2'))

    def test_overflowing_single_window(self):
        self.check_bad(self.fixture().replace(b'cycles=0x0000000000000064', b'cycles=0xffffffffffffffff'))

    def test_sum_exceeds_forward_window(self):
        raw = self.fixture()
        for row in self.rows:
            raw = raw.replace(row.encode(), (row.split('cycles=')[0] + 'cycles=0x0000000400000000').encode())
        self.check_bad(raw)

    def test_truncated_profile(self):
        self.check_bad(self.fixture().replace(b'YOLO_PROFILE_END', b'INCOMPLETE'))

    def test_detection_regression(self):
        self.check_bad(self.fixture().replace(b'car 844/1000', b'car 843/1000'))

    def test_malformed_cycle_field(self):
        self.check_bad(self.fixture().replace(b'cycles=0x0000000000000064', b'cycles=0x64'))

    def test_rows_before_forward_timer_output(self):
        raw = self.fixture().replace(b'YOLO_FORWARD_CYCLES=0x0000000400000000\n', b'')
        self.check_bad(raw + b'YOLO_FORWARD_CYCLES=0x0000000400000000\n')

    def tcm_fixture(self):
        return (self.fixture().replace(b'YOLO_FIXED START\n',
                b'TCM_STACK begin bottom=0x0000e000 top=0x00010000 sp=0x0000ffe0 guard_bytes=256\nYOLO_FIXED START\n') +
                b'TCM_STACK finish sp=0x0000ffe0 guard_changed_words=0 main_return=0x00000000 guard=PASS\n')

    def test_tcm_complete_profile_and_exit(self):
        result = summarize(self.tcm_fixture(), self.graph, 100_000_000)
        self.assertEqual(result['tcm_stack']['result'], 'TCM_STACK_COMPLETION_PASS')
        self.assertNotIn('tcm_stack', summarize(self.fixture(), self.graph, 100_000_000))

    def test_tcm_truncated_after_profile(self):
        self.check_bad(self.tcm_fixture().split(b'TCM_STACK finish')[0])

    def test_tcm_guard_failure_after_profile(self):
        self.check_bad(self.tcm_fixture().replace(b'guard_changed_words=0', b'guard_changed_words=1'))
        self.check_bad(self.tcm_fixture().replace(b'guard=PASS', b'guard=FAIL'))

    def test_tcm_nonzero_main_return(self):
        self.check_bad(self.tcm_fixture().replace(b'main_return=0x00000000', b'main_return=0x00000004'))

    def test_tcm_finish_before_profile_end(self):
        raw = self.tcm_fixture()
        first, last = raw.split(b'TCM_STACK finish')
        raw = first.replace(b'YOLO_PROFILE_END\n', b'TCM_STACK finish' + last + b'YOLO_PROFILE_END\n')
        self.check_bad(raw)

    def test_tcm_range_boundaries(self):
        for before, after in [(b'bottom=0x0000e000', b'bottom=0x0000e004'),
                              (b'top=0x00010000', b'top=0x80fff000'),
                              (b'sp=0x0000ffe0', b'sp=0x0000e0fc'),
                              (b'sp=0x0000ffe0', b'sp=0x00010000'),
                              (b'guard_bytes=256', b'guard_bytes=128')]:
            with self.subTest(after=after):
                self.check_bad(self.tcm_fixture().replace(before, after))

    def test_tcm_missing_or_repeated_begin(self):
        raw = self.tcm_fixture()
        line = next(s for s in raw.splitlines(keepends=True) if s.startswith(b'TCM_STACK begin'))
        self.check_bad(raw.replace(line, b''))
        self.check_bad(raw.replace(line, line + line))

    def test_tcm_failure_marker_without_begin(self):
        self.check_bad(self.fixture() + b'TCM_STACK_FAIL range\n')


if __name__ == '__main__':
    unittest.main()
