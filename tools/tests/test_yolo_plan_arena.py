"""Lifetime edge cases for non-in-place execution and final detector outputs."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from yolo_plan_arena import lifetimes, plan, read_graph, render_header, validate


def layer(kind=1, size=64, sources=()):
    return dict(kind=kind, bytes=size, sources=list(sources))


class ArenaTests(unittest.TestCase):
    def test_chain_reuses_only_after_final_read(self):
        layers = [layer(), layer(), layer()]
        result = plan(layers)
        self.assertEqual(result['offsets'], [0, 64, 0])
        self.assertEqual(result['last_use'], [1, 2, 2])
        self.assertEqual(result['arena_bytes'], 128)

    def test_shortcut_keeps_skip_and_previous_input(self):
        layers = [layer(), layer(), layer(3, sources=[0])]
        result = plan(layers)
        self.assertEqual(result['last_use'], [2, 2, 2])
        self.assertEqual(result['offsets'], [0, 64, 128])

    def test_route_keeps_distant_source(self):
        layers = [layer(), layer(), layer(), layer(2, sources=[0])]
        result = plan(layers)
        self.assertEqual(result['last_use'][0], 3)
        self.assertNotEqual(result['offsets'][3], result['offsets'][0])

    def test_concat_cannot_overwrite_either_source(self):
        result = plan([layer(), layer(), layer(2, 128, [0, 1])])
        self.assertEqual(result['offsets'], [0, 64, 128])
        self.assertEqual(result['arena_bytes'], 256)

    def test_heads_survive_to_postprocess(self):
        layers = [layer(), layer(7), layer(), layer(7)]
        result = plan(layers)
        self.assertEqual(result['last_use'], [1, 4, 3, 4])
        with self.assertRaises(ValueError):
            validate(layers, [0, 64, 0, 64], 128)

    def test_reject_same_stage_input_output_alias(self):
        with self.assertRaises(ValueError):
            validate([layer(), layer()], [0, 0], 64)

    def test_reject_oob_and_unaligned(self):
        for offsets, size in [([0, 64], 64), ([0, 65], 160)]:
            with self.assertRaises(ValueError):
                validate([layer(), layer()], offsets, size)

    def test_reject_future_edge(self):
        with self.assertRaises(ValueError):
            lifetimes([layer(), layer(2, sources=[2])])

    def test_alignment_pads_full_allocation(self):
        result = plan([layer(size=33), layer(size=1)])
        self.assertEqual(result['offsets'], [0, 64])
        self.assertEqual(result['arena_bytes'], 96)

    def test_current_graph_and_hash_bound_header(self):
        path = Path(__file__).resolve().parents[2]/'sw/yolo_fixed/model_graph.h'
        layers, digest = read_graph(path)
        result = plan(layers)
        self.assertEqual(len(layers), 131)
        self.assertEqual(result['retained_heads'], [121, 130])
        self.assertEqual([result['last_use'][i] for i in [121,130]], [131,131])
        self.assertEqual(result['original_bytes'], 7502200)
        self.assertEqual(result['arena_bytes'], 870400)
        self.assertGreaterEqual(result['arena_bytes'], result['peak_live_padded_bytes'])
        self.assertNotEqual(render_header(result,digest), render_header(result,'0'*64))


if __name__ == '__main__':
    unittest.main()
