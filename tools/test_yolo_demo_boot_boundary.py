"""Offline parser regressions. Optional YOLO_BOOT_BOUNDARY_RAW binds a real capture.

Never opens devices; normal fixture and layout use frozen A97/A98 artifacts.
Run with python -B tools/test_yolo_demo_boot_boundary.py -v.
"""
import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from check_tcm_image import check as check_tcm
from yolo_demo_report import parse_uart, sha


class BootBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        profile = ROOT / 'docs/validation/20261025-a97-pool-separable-production/profile'
        cls.layout = check_tcm(profile / 'yolo_fixed.elf', profile / 'yolo_fixed.bin', tcm_stack=True)
        cls.raw = (ROOT / 'docs/validation/20261025-a98-pool-separable-qualification/14_dog_restore/uart.log').read_bytes()
        cls.clean = cls.raw[cls.raw.index(b'RV32BOOT1'):]
        cls.expected = parse_uart(cls.clean, cls.layout)

    def assert_results_equal(self, actual, reference=None):
        reference = self.expected if reference is None else reference
        for key in ('detections', 'head_fnv1a', 'forward_cycles', 'tcm_bytes', 'runtime_pc', 'runtime_checks'):
            self.assertEqual(actual[key], reference[key], key)

    def test_archived_normal_restore(self):
        result = parse_uart(self.raw, self.layout)
        self.assert_results_equal(result)
        self.assertEqual(result['uart_sha256'], sha(self.raw))
        self.assertEqual(len(result['detections']), 6)
        self.assertEqual(result['head_fnv1a'], ['99860b0f', '98155281'])

    def test_crlf_and_lf_boot_terminators(self):
        for raw in (self.clean, self.clean.replace(b'\r', b'')):
            with self.subTest(raw=raw[:12]):
                result = parse_uart(raw, self.layout)
                self.assert_results_equal(result)
                self.assertEqual(result['prefix_bytes'], 0)

    def test_unterminated_ascii_residue_is_separately_bound(self):
        prefix = b'L09 I=1\r\nR03 48520010100000007e4b078004380100 722d'
        raw = prefix + self.clean
        result = parse_uart(raw, self.layout)
        self.assert_results_equal(result)
        self.assertEqual(result['uart_sha256'], sha(raw))
        self.assertEqual(result['prefix_bytes'], len(prefix))
        self.assertEqual(result['prefix_sha256'], sha(prefix))
        self.assertTrue(result['prefix_ascii'])

    def test_old_errors_before_boot_are_scoped_to_prefix(self):
        prefix = b'OLD [TRAP] guard=FAIL GO\n'
        result = parse_uart(prefix + self.clean, self.layout)
        self.assert_results_equal(result)
        self.assertEqual(result['prefix_bytes'], len(prefix))

    def test_binary_prefix_does_not_relax_post_boot_ascii(self):
        result = parse_uart(b'\xff\x00old' + self.clean, self.layout)
        self.assertFalse(result['prefix_ascii'])
        self.assertEqual(result['prefix_bytes'], 5)
        with self.assertRaises(UnicodeDecodeError):
            parse_uart(self.clean + b'\xff', self.layout)

    def test_real_interrupted_R03_capture_if_supplied(self):
        name = os.environ.get('YOLO_BOOT_BOUNDARY_RAW')
        if not name:
            self.skipTest('Set YOLO_BOOT_BOUNDARY_RAW to the preserved interrupted R03 capture')
        raw = Path(name).read_bytes()
        prefix_size = raw.index(b'RV32BOOT1')
        self.assertGreater(prefix_size, 0)
        self.assertFalse(raw[:prefix_size].endswith(b'\n'))
        self.assertIn(b'R03 ', raw[:prefix_size])
        result = parse_uart(raw, self.layout)
        clean_result = parse_uart(raw[prefix_size:], self.layout)
        self.assert_results_equal(result, clean_result)
        self.assertEqual(result['uart_sha256'], sha(raw))
        self.assertEqual(result['prefix_bytes'], prefix_size)
        self.assertEqual(result['prefix_sha256'], sha(raw[:prefix_size]))
        self.assertEqual(result['head_fnv1a'], ['99860b0f', '98155281'])
        self.assertEqual(len(result['detections']), 6)

    def test_duplicate_boot_anywhere_including_prefix_rejected(self):
        for raw in (b'RV32BOOT1\noldpartial' + self.clean,
                    self.clean + b'RV32BOOT1\r\n',
                    b'oldRV32BOOT1partial' + self.clean,
                    self.clean + b'RV32BOOT1'):
            with self.subTest(raw=raw[:25]), self.assertRaises(ValueError):
                parse_uart(raw, self.layout)

    def test_missing_or_incomplete_boot_rejected(self):
        for token in (b'', b'RV32BO', b'RV32BOOT1', b'RV32BOOT1\r', b'RV32BOOT1X\n', b'RV32BOOT1\r\r\n'):
            raw = self.clean.replace(b'RV32BOOT1\r\n', token, 1)
            with self.subTest(token=token), self.assertRaises(ValueError):
                parse_uart(raw, self.layout)

    def test_all_post_boot_error_markers_remain_fatal(self):
        for marker in (b'[TRAP]', b'BAD HASH', b'HASH FAIL', b'STAGE_FAIL', b'guard=FAIL', b'YOLO_INPUT_BAD'):
            with self.subTest(marker=marker), self.assertRaises(ValueError):
                parse_uart(b'oldpartial' + self.clean + marker + b'\n', self.layout)

    def test_duplicate_required_markers_rejected(self):
        for marker in (b'GO', b'YOLO_FIXED START', b'YOLO_INPUT 307200', b'YOLO_INPUT_OK', b'YOLO_FIXED PASS'):
            with self.subTest(marker=marker), self.assertRaises(ValueError):
                parse_uart(b'oldpartial' + self.clean + marker + b'\n', self.layout)

    def test_post_boot_order_remains_strict(self):
        raw = self.clean.replace(b'GO\r\n', b'', 1) + b'GO\r\n'
        with self.assertRaisesRegex(ValueError, 'Out-of-order'):
            parse_uart(b'oldpartial' + raw, self.layout)

    def test_tcm_and_stack_checks_remain_strict(self):
        for raw in (self.clean.replace(b'pc=0x00008328', b'pc=0x80008328'),
                    self.clean.replace(b'bytes=24432', b'bytes=24431'),
                    self.clean.replace(b'guard_changed_words=0', b'guard_changed_words=1'),
                    self.clean.split(b'TCM_STACK finish')[0]):
            with self.subTest(raw=raw[-80:]), self.assertRaises(ValueError):
                parse_uart(b'oldpartial' + raw, self.layout)

    def test_detection_checks_remain_strict(self):
        for raw in (self.clean.replace(b'detections=6', b'detections=7'),
                    self.clean.replace(b'[188,45,281,94]', b'[188,45,321,94]'),
                    self.clean.replace(b'car 844/1000', b'car 1001/1000'),
                    self.clean.replace(b'car 844/1000 [', b'!car 844/1000 [')):
            with self.subTest(raw=raw[-200:]), self.assertRaises(ValueError):
                parse_uart(b'oldpartial' + raw, self.layout)

    def test_repeated_heads_and_cycles_rejected(self):
        for line in self.clean.splitlines():
            if line.startswith((b'YOLO_FIXED HEADS', b'YOLO_FORWARD_CYCLES=')):
                with self.subTest(line=line), self.assertRaises(ValueError):
                    parse_uart(self.clean + line + b'\n', self.layout)


if __name__ == '__main__':
    unittest.main()
