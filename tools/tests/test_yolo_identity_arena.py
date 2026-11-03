"""Planner proof and rejected unsafe plans; no FPGA/production mutation."""
import copy,importlib.util,random,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('identity',ROOT/'tools/yolo_plan_identity_arena.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
spec=importlib.util.spec_from_file_location('original',ROOT/'tools/yolo_plan_arena.py');original=importlib.util.module_from_spec(spec);spec.loader.exec_module(original)

class IdentityArena(unittest.TestCase):
    def setUp(self):
        self.layers,_=p.read_graph(ROOT/'sw/yolo_fixed/model_graph.h');self.plan=p.build(self.layers)
    def rejects(self,plan,layers=None):
        with self.assertRaises(ValueError):p.verify(layers or self.layers,plan)
    def test_fixed_graph_and_original_lifetimes(self):
        old_layers,_=original.read_graph(ROOT/'sw/yolo_fixed/model_graph.h');old=original.plan(old_layers)
        self.assertEqual(old['arena_bytes'],870400);self.assertEqual(self.plan['arena_bytes'],819200)
        self.assertEqual(len(self.plan['forwarded_layers']),20);self.assertEqual(self.plan['forwarded_tensor_bytes'],522700)
        # Independent original last-read calculation, unioned by storage root.
        last,_=original.lifetimes(old_layers)
        for group in self.plan['groups']:
            self.assertEqual(group['last_use'],max(last[i] for i in group['members']))
        self.assertEqual(self.plan['retained_heads'],[121,130]);p.verify(self.layers,self.plan)
    def test_naive_old_offsets_are_unsafe(self):
        old_layers,_=original.read_graph(ROOT/'sw/yolo_fixed/model_graph.h');old=original.plan(old_layers)
        bad=copy.deepcopy(self.plan);bad['arena_bytes']=old['arena_bytes'];bad['offsets']=list(old['offsets'])
        for i in bad['forwarded_layers']:bad['offsets'][i]=bad['offsets'][i-1]
        self.rejects(bad)
    def test_overwrite_live_source(self):
        bad=copy.deepcopy(self.plan);bad['offsets'][1]=bad['offsets'][0];self.rejects(bad)
    def test_head_retention_cannot_be_dropped(self):
        bad=copy.deepcopy(self.plan);head=next(g for g in bad['groups'] if 121 in g['members']);head['last_use']=121;self.rejects(bad)
    def test_false_alias_multiplier_and_shape(self):
        for field,value in [('q24',16777215),('input_shape',[1,1,1])]:
            layers=copy.deepcopy(self.layers);layers[7][field]=value;self.rejects(self.plan,layers)
    def test_raw_input_is_not_a_saturated_producer(self):
        layers=copy.deepcopy(self.layers);layers[6]['kind']=5;self.rejects(self.plan,layers)
    def test_offset_tail_and_root_mutations(self):
        bad=copy.deepcopy(self.plan);bad['offsets'][7]+=32;self.rejects(bad)
        bad=copy.deepcopy(self.plan);bad['arena_bytes']-=32;self.rejects(bad)
        bad=copy.deepcopy(self.plan);bad['roots'][0]=-1;self.rejects(bad)
    def test_inclusive_consumer_overlap(self):
        # A live producer cannot be overwritten by its own nonidentity consumer.
        bad=copy.deepcopy(self.plan);bad['offsets'][2]=bad['offsets'][1];self.rejects(bad)
    def test_domain_counterexample(self):
        quant=lambda x:max(-127,min(127,x))
        self.assertTrue(all(quant(x)==x for x in range(-127,128)))
        self.assertNotEqual(quant(-128),-128)
    def test_synthetic_causal_branches(self):
        rng=random.Random(70)
        for trial in range(40):
            layers=[]
            for i in range(35):
                kind=6 if i and layers[-1]['kind']==1 and rng.randrange(3)==0 else 1
                if i>2 and rng.randrange(4)==0:kind=2
                if i==34:kind=7
                sources=[rng.randrange(i)] if kind==2 else []
                layers.append(dict(index=i,kind=kind,input_shape=[1,32,1],shape=[1,32,1],bytes=32,sources=sources,q24=16777216))
            plan=p.build(layers);p.verify(layers,plan)
    def test_reject_noncausal_reference(self):
        layers=copy.deepcopy(self.layers);layers[110]['sources']=[110]
        with self.assertRaises(ValueError):p.build(layers)

if __name__=='__main__':unittest.main()
