"""Regression checks for false pipeline evidence, not hardware acceptance."""
import copy
from collections import Counter
import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

REPO=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('coremark_ila',REPO/'tools/coremark_ila.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
ELF=REPO/'docs/validation/20261023-a58-coremark-tcm/tcm/coremark.elf'


def sample(pc=0x8e58,**flags):
    row={name:0 for name,_ in c.CHANNELS}
    for bit in range(2,32):row[f'mem_pc_{bit}']=(pc>>bit)&1
    row.update(mem_valid=1,mem_commit=1);row.update(flags)
    return row


def schema():
    return dict(samples=512,clock='ui_clk',channels=[dict(index=i,name=n,net=v) for i,(n,v) in enumerate(c.CHANNELS)])


class PipelineEvidenceTests(unittest.TestCase):
    def setUp(self):self.ranges=c.elf_functions(ELF.read_bytes())

    def test_real_elf_three_algorithms(self):
        self.assertEqual(self.ranges['core_list_mergesort'],dict(start=0x8e58,end=0x9008,bytes=432))
        self.assertEqual(len(self.ranges),3)

    def test_held_mem_pc_not_repeated_retirement(self):
        rows=[sample(pipe_freeze=1,data_wait=1) for _ in range(7)]+[sample()]
        s,_=c.analyze(rows,self.ranges,'core_list_mergesort')
        self.assertEqual(s['counts']['retired'],1)
        self.assertEqual(s['local_cpi'],8)
        self.assertEqual(s['function_retired']['core_list_mergesort'],1)

    def test_invalid_mem_pc_does_not_identify_algorithm(self):
        rows=[sample(mem_valid=0,mem_commit=0),sample(pc=0x8000)]
        with self.assertRaisesRegex(ValueError,'Expected algorithm'):c.analyze(rows,self.ranges,'core_list_mergesort')

    def test_raw_branch_held_during_muldiv_is_not_event(self):
        s,_=c.analyze([sample(branch_raw=1,branch_mispred_raw=1,muldiv_wait=1,pipe_freeze=1),sample()],self.ranges)
        self.assertEqual(s['counts']['branch_events'],0)
        self.assertEqual(s['counts']['mispredict_events'],0)

    def test_overlapping_waits_not_summed(self):
        s,_=c.analyze([sample(pipe_freeze=1,data_wait=1,muldiv_wait=1,if_wait=1),sample()],self.ranges)
        self.assertEqual(s['stall_fractions_overlapping']['data_wait'],.5)
        self.assertEqual(s['stall_fractions_overlapping']['muldiv_wait'],.5)
        self.assertEqual(s['stall_fractions_overlapping']['if_wait'],0)

    def test_invalid_pipeline_combinations_rejected(self):
        for flags in [dict(mem_valid=0),dict(data_wait=1),dict(muldiv_wait=1),dict(trap_enter=1)]:
            with self.subTest(flags=flags),self.assertRaises(ValueError):c.analyze([sample(**flags)],self.ranges)

    def test_no_retirement_or_empty_rejected(self):
        for rows in [[],[sample(pipe_freeze=1)]]:
            with self.assertRaises(ValueError):c.analyze(rows,self.ranges)

    def test_binding_rejects_wrong_elf_fic_or_schema(self):
        s=schema();e=ELF.read_bytes();f=b'fixture FIC'
        s.update(elf_sha256=c.sha(e),fic_sha256=c.sha(f),function_ranges=self.ranges)
        c.validate_binding(s,f,e)
        for which in ['elf','fic','channels','ranges','clock']:
            bad=copy.deepcopy(s);be=e;bf=f
            if which=='elf':be=e+b'drift'
            if which=='fic':bf=f+b'drift'
            if which=='channels':bad['channels'][0]['name']='wrong'
            if which=='ranges':bad['function_ranges']['core_list_mergesort']['start']+=4
            if which=='clock':bad['clock']='nt_sys_clk'
            with self.subTest(which=which),self.assertRaises(ValueError):c.validate_binding(bad,bf,be)

    def test_wdf_duplicate_name_metadata_allowed_actual_records_unique(self):
        s=schema();rows=[sample() for _ in range(512)];raw=b''
        for item in s['channels']:
            key=item['net'].encode('utf-16-be')
            prefix=struct.pack('>I',len(key))
            raw+=prefix+key+b'not data'+prefix+key+struct.pack('>II',3,1024)+''.join(str(row[item['name']]) for row in rows).encode('utf-16-be')
        self.assertEqual(c.read_wdf(raw,s),rows)
        key=s['channels'][0]['net'].encode('utf-16-be')
        record=struct.pack('>I',len(key))+key+struct.pack('>II',3,1024)+('0'*512).encode('utf-16-be')
        for invalid in [raw+record,raw[:-1],raw.replace(('0'*512).encode('utf-16-be'),('x'+'0'*511).encode('utf-16-be'),1)]:
            with self.assertRaises(ValueError):c.read_wdf(invalid,s)

    def test_decoder_against_archived_physical_startup_wdf(self):
        # File-format compatibility only: these old startup channels are NOT CoreMark evidence.
        old=REPO/'docs/validation/20261021-a37-startup-debug/07_original_existing_ila'
        ref=json.loads((old/'summary.json').read_text())
        raw=(old/'capture.wdf').read_bytes()
        self.assertEqual(c.sha(raw),ref['waveform_sha256'])
        s=dict(samples=512,channels=[dict(name=n,net=n) for n in ref['signals']])
        rows=c.read_wdf(raw,s)
        for name,v in ref['signals'].items():
            self.assertEqual(dict(Counter(str(row[name]) for row in rows)),v['counts'])

    def test_malformed_elf_rejected(self):
        with self.assertRaises(ValueError):c.elf_functions(b'\x7fELF')
        bad=bytearray(ELF.read_bytes());struct.pack_into('<H',bad,46,0)
        with self.assertRaises(ValueError):c.elf_functions(bad)

    def test_plan_triggers_actual_entry_and_valid_retirement(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);s=c.prepare(root/'unused.adf',ELF,root/'probe')
            fic=root/'probe/coremark_pipeline.fic'
            self.assertIn('clockChannel=ui_clk',fic.read_text())
            plan=c.capture_plan(s,fic,ELF,root/'plans')
            self.assertEqual(plan['result'],'CAPTURE_PLAN_ONLY_NOT_EXECUTED')
            labels=[name for name,_ in c.CHANNELS]
            for item in plan['plans']:
                bits=list(reversed(item['trigger_binary_msb_first']))
                pc=sum(int(bits[labels.index(f'mem_pc_{b}')])<<b for b in range(2,32))
                self.assertEqual(pc,self.ranges[item['function']]['start'])
                self.assertEqual(bits[labels.index('mem_valid')],'1')
                self.assertEqual(bits[labels.index('mem_commit')],'1')
                self.assertEqual(bits[labels.index('pipe_freeze')],'0')
                script=Path(item['script']).read_text()
                self.assertIn('dbg_set_capture -type 0 -windows 1 -position 1',script)
                self.assertNotIn('dbg_program',script)


if __name__=='__main__':unittest.main()
