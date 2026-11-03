"""Synthetic parser checks; these are not physical captures."""
from pathlib import Path
import copy,math,sys,unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'))
import summarize_post8_phases as p
GRAPH=ROOT/'sw/yolo_fixed/model_graph.h'
def fixture():
 raw=(ROOT/'docs/validation/20261024-a77-dw5-pack-profile/01_profile_run1/uart.log').read_bytes().replace(b'TCM_STACK finish',b'PHASE_INSERT\nTCM_STACK finish')
 rows=[]
 for shape in p.expected_shapes(GRAPH.read_text()).values():
  v=shape['expected'].copy();n=v['samples'];v.update(polls=n,max_task=100000,cache=100 if shape['cached'] else 0,weight=100,setup=n*10,pack=0 if shape['cached'] else v['vectors']*2,write=v['vectors']*2,wait=3*v['dots']+n*10,read=0,q24=v['rwords']*2,engine=3*v['dots'])
  v['task']=sum(v[k] for k in p.WIRE_PHASES)+n*100;v['max_task']=math.ceil(v['task']/n)+10
  rows.append('YOLO_BLOCK_PHASE '+' '.join(f'{k}={v[k]}' for k in p.COUNTS)+''.join(f' {k}=0x{v[k]:016x}' for k in p.CYCLES))
 block='YOLO_BLOCK_PHASE_BEGIN stride=64 tail=group_last clock_bits=32 calibration_min=6 calibration_max=6\n'+'\n'.join(rows)+'\nYOLO_BLOCK_PHASE_END'
 return raw.replace(b'PHASE_INSERT',block.encode())
class Parser(unittest.TestCase):
 def test_full_model(self):
  out=p.summarize(fixture(),GRAPH);self.assertEqual(len(out['layers']),55);self.assertEqual(sum(x['cached'] for x in out['layers']),53);self.assertEqual(out['semantics']['q24'],'post_read_unpack_store')
 def test_independent_small_geometry(self):
  line=' {1,1,9,10,1,9,9,1,1,1,0,'+','.join(['0']*14)+'}, /* layer 0 */'
  e=p.expected_shapes(line)[0]['expected'];self.assertEqual((e['tasks'],e['samples'],e['batches'],e['rwords'],e['dots']),(4,2,2,17,130))
 def test_mutations(self):
  raw=fixture()
  cases=[(b'tasks=',b'tasks=9'),(b'rwords=',b'rwords=9'),(b'dots=',b'dots=9'),(b' engine=0x',b' engine=0x1'),(b' read=0x0000000000000000',b' read=0x0000000000000001'),(b'calibration_min=6',b'calibration_min=0'),(b'YOLO_BLOCK_PHASE_END',b'BAD_END'),(b' cache=0x0000000000000064',b' cache=0x0000000000000000')]
  for before,after in cases:
   with self.subTest(before=before),self.assertRaises(ValueError):p.summarize(raw.replace(before,after,1),GRAPH)
 def test_duplicate_and_reorder(self):
  raw=fixture();lines=raw.splitlines();ids=[i for i,x in enumerate(lines) if x.startswith(b'YOLO_BLOCK_PHASE ')]
  lines[ids[1]]=lines[ids[0]]
  with self.assertRaises(ValueError):p.summarize(b'\n'.join(lines),GRAPH)
if __name__=='__main__':unittest.main(verbosity=2)
