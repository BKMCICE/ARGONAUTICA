"""Prove the actual DDR SoC address predicates are pairwise disjoint."""
import itertools
import re
import unittest
from pathlib import Path


class DdrDecodeTest(unittest.TestCase):
    def test_all_32_bit_addresses_have_at_most_one_slave(self):
        source = (Path(__file__).resolve().parents[2] / 'rtl/top/soc_top_ddr.v').read_text()
        predicates = re.findall(
            r"assign sel\[(S_\w+)\]\s*=\s*dmem_addr\[(\d+):(\d+)\]\s*==\s*(0|\d+'[bh][0-9a-fA-F]+);", source)
        count = int(re.search(r'localparam NS\s*=\s*(\d+)', source)[1])
        self.assertEqual(len(predicates), count)
        masks = []
        for name, high, low, literal in predicates:
            high, low = int(high), int(low)
            width = high-low+1
            if literal == '0':
                value = 0
            else:
                declared, radix, digits = re.fullmatch(r"(\d+)'([bh])([0-9a-fA-F]+)", literal).groups()
                self.assertEqual(int(declared), width)
                value = int(digits, 2 if radix == 'b' else 16)
            self.assertLess(value, 1 << width)
            masks.append((name, ((1 << width)-1) << low, value << low))
        for (a, ma, va), (b, mb, vb) in itertools.combinations(masks, 2):
            with self.subTest(slaves=(a,b)):
                # A shared constrained bit must differ, so no 32-bit word
                # can satisfy both source predicates simultaneously.
                self.assertNotEqual((va ^ vb) & ma & mb, 0)


if __name__ == '__main__':
    unittest.main()
