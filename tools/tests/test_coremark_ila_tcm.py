"""False-evidence rejection and schema tests; fixtures are never board evidence."""
import copy,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import coremark_ila_tcm as c
R=Path(__file__).resolve().parents[2]
ELF=R/'docs/validation/20261023-a58-coremark-tcm/tcm/coremark.elf'
def row(pc=0x8e58,**flags):
    r={name:0 for name in c.NAMES}
    for bit in range(2,16):r[f'mem_pc_{bit}']=(pc>>bit)&1
    r.update(mem_pc_upper_zero=int(pc>>16==0),mem_valid=1,mem_commit=1);r.update(flags);return r
class TcmProbeTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.d=Path(self.tmp.name);self.s=c.prepare(self.d/'unused.adf',ELF,self.d/'p')
        self.f=self.d/'p/coremark_tcm26.fic';self.expected='core_list_mergesort'
    def analyze(self,rows):return c.analyze(rows,self.s,self.expected)
    def test_exact_delay_and_held_commit(self):
        rows=[row(pipe_freeze=1,data_wait=1) for _ in range(511)]+[row()]
        result,decoded=self.analyze(rows)
        self.assertEqual(result['counts']['retired'],1);self.assertEqual(result['local_cpi'],512)
        self.assertTrue(all(x['cpu_sample_offset_cycles']==-1 for x in decoded))
    def test_ddr_and_other_high_aliases_cannot_trigger_algorithm(self):
        for pc in [0x80008e58,0x00018e58,0x40008e58]:
            with self.subTest(pc=pc),self.assertRaisesRegex(ValueError,'exact-domain'):self.analyze([row(pc)]*512)
    def test_outside_tcm_full_pc_is_explicitly_unknown(self):
        result,decoded=self.analyze([row()]+[row(0x80008e58)]*511)
        self.assertEqual(result['counts']['retired_outside_tcm'],511)
        self.assertEqual(decoded[-1]['mem_pc'],'');self.assertEqual(decoded[-1]['mem_pc_exact'],0)
        self.assertEqual(result['function_retired'][self.expected],1)
    def test_invalid_stalls_commit_trap_and_partial_capture(self):
        for rows in [[row(mem_valid=0)]*512,[row(data_wait=1)]*512,[row(muldiv_wait=1)]*512,[row(trap_enter=1)]*512,[row()]*511]:
            with self.assertRaises(ValueError):self.analyze(rows)
    def test_overlapping_waits_not_exclusive_attribution(self):
        result,_=self.analyze([row(pipe_freeze=1,data_wait=1,muldiv_wait=1,if_wait=1)]*256+[row()]*256)
        self.assertEqual(result['stall_fractions_overlapping']['data_wait'],.5)
        self.assertEqual(result['stall_fractions_overlapping']['muldiv_wait'],.5)
        self.assertEqual(result['stall_fractions_overlapping']['if_wait'],0)
        self.assertNotIn('branch_events',result['counts'])
    def test_binding_rejects_wrong_delay_fic_elf_channels(self):
        c.validate_binding(self.s,self.f.read_bytes(),ELF.read_bytes())
        for mode in ['delay','channel','clock','elf','fic']:
            s=copy.deepcopy(self.s);f=self.f.read_bytes();e=ELF.read_bytes()
            if mode=='delay':s['sample_delay_cpu_cycles']=0
            if mode=='channel':s['channels'][0]['net']='other'
            if mode=='clock':s['clock']='nt_sys_clk'
            if mode=='elf':e+=b'x'
            if mode=='fic':f+=b'x'
            with self.subTest(mode=mode),self.assertRaises(ValueError):c.validate_binding(s,f,e)
    def test_plan_requires_exact_domain_and_retirement(self):
        p=c.capture_plan(self.s,self.f,ELF,self.d/'plan')
        for item in p['plans']:
            bits=list(reversed(item['trigger_binary_msb_first']))
            pc=sum(int(bits[c.NAMES.index(f'mem_pc_{b}')])<<b for b in range(2,16))
            self.assertEqual(pc,self.s['function_ranges'][item['function']]['start'])
            for n in ['mem_pc_upper_zero','mem_valid','mem_commit']:self.assertEqual(bits[c.NAMES.index(n)],'1')
            self.assertEqual(bits[c.NAMES.index('pipe_freeze')],'0')
            text=Path(item['script']).read_text();self.assertNotIn('dbg_program',text)
            self.assertIn('dbg_set_capture -type 0 -windows 1 -position 1',text)
if __name__=='__main__':unittest.main()
