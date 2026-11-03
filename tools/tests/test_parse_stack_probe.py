import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from parse_stack_probe import parse

ROW=(b'STACK_PROBE start=0x80fef000 top=0x80fff000 static_end=0x801ceb24 '
     b'lowest_changed=0x80ffee00 touched_bytes=512 guard_bytes=256 guard_changed_words=0 '
     b'snapshot_sp=0x80fff000 main_return=0x00000000 guard=PASS\r\n')

class StackSnapshotTests(unittest.TestCase):
    def test_valid_snapshot(self):
        self.assertEqual(parse(ROW,stack_top=0x80fff000,static_end=0x801ceb24)['touched_bytes'],512)
    def test_untouched_window(self):
        row=ROW.replace(b'80ffee00',b'80fff000').replace(b'touched_bytes=512',b'touched_bytes=0')
        self.assertEqual(parse(row)['touched_bytes'],0)
    def test_missing_or_duplicate(self):
        for raw in [b'',ROW+ROW]:
            with self.assertRaises(ValueError): parse(raw)
    def test_truncated(self):
        with self.assertRaises(ValueError): parse(ROW[:60])
    def test_bad_arithmetic(self):
        with self.assertRaises(ValueError): parse(ROW.replace(b'touched_bytes=512',b'touched_bytes=508'))
    def test_static_overlap(self):
        with self.assertRaises(ValueError): parse(ROW.replace(b'801ceb24',b'80fef004'))
    def test_wrong_elf(self):
        with self.assertRaises(ValueError): parse(ROW,stack_top=0x8000f000)
        with self.assertRaises(ValueError): parse(ROW,static_end=0x801ceb20)
    def test_guard_status_inconsistent(self):
        with self.assertRaises(ValueError): parse(ROW.replace(b'guard=PASS',b'guard=FAIL'))
    def test_guard_corruption_requires_explicit_negative(self):
        row=ROW.replace(b'80ffee00',b'80fef004').replace(b'touched_bytes=512',b'touched_bytes=65532').replace(b'guard_changed_words=0',b'guard_changed_words=1').replace(b'guard=PASS',b'guard=FAIL')
        with self.assertRaises(ValueError): parse(row)
        self.assertEqual(parse(row,expect_guard_failure=True)['result'],'EXPECTED_GUARD_CORRUPTION_PASS')
    def test_guard_count_contradiction(self):
        with self.assertRaises(ValueError): parse(ROW.replace(b'guard_changed_words=0',b'guard_changed_words=1'))
    def test_non_restored_sp_or_main_error(self):
        for row in [ROW.replace(b'snapshot_sp=0x80fff000',b'snapshot_sp=0x80ffeff0'),ROW.replace(b'main_return=0x00000000',b'main_return=0x00000003')]:
            with self.assertRaises(ValueError): parse(row)
    def test_unaligned_or_out_of_range(self):
        for lowest in [b'80ffee01',b'80fef000',b'81000000']:
            with self.assertRaises(ValueError): parse(ROW.replace(b'80ffee00',lowest))
    def test_tcm_stack_requires_explicit_domain(self):
        row=(ROW.replace(b'80fef000',b'0000e000').replace(b'80fff000',b'00010000')
             .replace(b'80ffee00',b'0000fe00'))
        with self.assertRaises(ValueError): parse(row,window_bytes=8192)
        out=parse(row,window_bytes=8192,tcm_stack=True)
        self.assertEqual(out['touched_bytes'],512)
        self.assertIsNone(out['unpainted_static_to_window_gap_bytes'])
    def test_tcm_stack_rejects_code_region(self):
        row=(ROW.replace(b'80fef000',b'0000d000').replace(b'80fff000',b'00010000')
             .replace(b'80ffee00',b'0000fe00'))
        with self.assertRaises(ValueError): parse(row,window_bytes=12288,tcm_stack=True)
    def test_tcm_static_data_stays_ddr(self):
        row=(ROW.replace(b'80fef000',b'0000e000').replace(b'80fff000',b'00010000')
             .replace(b'80ffee00',b'0000fe00').replace(b'801ceb24',b'0000a000'))
        with self.assertRaises(ValueError): parse(row,window_bytes=8192,tcm_stack=True)

if __name__=='__main__':
    unittest.main()
