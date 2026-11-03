"""Reject stale domain sources, changed graph and unsafe forwarding layout."""
import copy,importlib.util,json,sys,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'))
import yolo_check_identity_forward as c

class Contract(unittest.TestCase):
    def test_reviewed_fixed_model(self):
        result=c.verify(ROOT)
        self.assertEqual(result['plan']['arena_bytes'],819200)
        self.assertEqual(len(result['plan']['forwarded_layers']),20)
    def test_changed_clip_source_rejected(self):
        original=Path.read_bytes;file=ROOT/'sw/yolo_fixed/main.c';touched=[]
        def raw(path):
            data=original(path)
            if path==file:
                token=b'if (value < -127) return -127;';self.assertEqual(data.count(token),1)
                data=data.replace(token,b'if (value < -128) return -128;');touched.append(True)
            return data
        with patch.object(Path,'read_bytes',raw),self.assertRaisesRegex(ValueError,'contract stale'):c.verify(ROOT)
        self.assertTrue(touched)
    def test_changed_graph_multiplier_rejected(self):
        original=Path.read_text;file=ROOT/'sw/yolo_fixed/model_graph.h';touched=[]
        def text(path,*a,**k):
            value=original(path,*a,**k)
            if path==file:
                lines=value.splitlines(keepends=True)
                for i,line in enumerate(lines):
                    if '/* layer 7 */' in line:
                        self.assertIn('16777216',line);lines[i]=line.replace('16777216','16777215');touched.append(True)
                value=''.join(lines)
            return value
        with patch.object(Path,'read_text',text),self.assertRaises(ValueError):c.verify(ROOT)
        self.assertTrue(touched)
    def test_header_offset_tampering_rejected(self):
        original=Path.read_text;file=ROOT/'sw/yolo_fixed/model_identity_arena.h'
        def text(path,*a,**k):
            data=original(path,*a,**k)
            return data.replace('819200u','819168u') if path==file else data
        with patch.object(Path,'read_text',text),self.assertRaisesRegex(ValueError,'header stale'):c.verify(ROOT)
    def test_coherent_bad_group_lifetime_rejected(self):
        original=c.planner.build
        def broken(layers):
            value=copy.deepcopy(original(layers));g=next(g for g in value['groups'] if 121 in g['members']);g['last_use']=121;return value
        with patch.object(c.planner,'build',broken),self.assertRaisesRegex(ValueError,'Lifetime'):c.verify(ROOT)
    def test_changed_quantizer_rejected(self):
        original=Path.read_bytes;file=ROOT/'rtl/periph/ai_q24_post.v';touched=[]
        def raw(path):
            data=original(path)
            if path==file:
                self.assertIn(b'-127',data);data=data.replace(b'-127',b'-128');touched.append(True)
            return data
        with patch.object(Path,'read_bytes',raw),self.assertRaisesRegex(ValueError,'contract stale'):c.verify(ROOT)
        self.assertTrue(touched)
    def test_changed_dw5_packer_rejected(self):
        original=Path.read_bytes;file=ROOT/'sw/yolo_fixed/dw5_pack_fast.h';touched=[]
        def raw(path):
            data=original(path)
            if path==file:
                self.assertIn(b'p[2]=0;',data)
                data=data.replace(b'p[2]=0;',b'p[2]=1;');touched.append(True)
            return data
        with patch.object(Path,'read_bytes',raw),self.assertRaisesRegex(ValueError,'contract stale'):c.verify(ROOT)
        self.assertTrue(touched)
if __name__=='__main__':unittest.main(verbosity=2)
