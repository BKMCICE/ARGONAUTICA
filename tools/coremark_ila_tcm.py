"""A63 registered26 TCM CoreMark observer. Preparation/decoding only; no devices.

PC[15:2] is qualified by a registered comparison PC[31:16]==0, so addresses
outside TCM cannot alias an algorithm. Every field has the same one-cycle lag.
The legacy47 decoder remains separate and unchanged.
"""
import argparse,csv,json
from pathlib import Path
from coremark_ila import elf_functions,read_wdf,sha,FUNCTIONS

FLAGS=['if_inflight','id_valid','ex_valid','mem_valid','mem_commit','pipe_freeze',
       'if_wait','load_use_wait','muldiv_wait','data_wait','trap_enter']
NAMES=[f'mem_pc_{i}' for i in range(2,16)]+['mem_pc_upper_zero']+FLAGS
CHANNELS=[(name,f'u_soc/u_core/pipeline_probe_q[{i}]') for i,name in enumerate(NAMES)]

def prepare(adf,elf,output):
    ranges=elf_functions(elf.read_bytes())
    if any(not (0<=v['start']<v['end']<=0x10000) or v['start']%4 for v in ranges.values()):
        raise ValueError('This probe requires algorithm functions entirely in aligned64KiB TCM')
    output.mkdir(parents=True,exist_ok=False)
    lines=['#Fabric Core Inserter Project File','#A63 registered26; all fields lag CPU by1 cycle',
      'Project.type=inserter',f'Project.device.designInputFile={adf.resolve().as_posix()}',
      'Project.device.ScanChain=1','Project.device.UserJtag=0','Project.Architecture=1 1 1 ',
      'Project.unit.dimension=1','Project.unit<0>.clockChannel=ui_clk','Project.unit<0>.clockEdge=Rising',
      'Project.unit<0>.ramType=1','Project.unit<0>.dataDepth=512','Project.unit<0>.dataEqualsTrigger=true',
      'Project.unit<0>.enablePowerOnInitData=false','Project.unit<0>.enableStorageQualification=false',
      'Project.unit<0>.triggerSequencerLevels=1','Project.unit<0>.enableMultiWindow=false',
      'Project.unit<0>.triggerPortCount=1']
    lines += [f'Project.unit<0>.triggerChannel<0><{i}>={net}' for i,(_,net) in enumerate(CHANNELS)]
    lines += ['Project.unit<0>.triggerMatchCount<0>=1','Project.unit<0>.triggerMatchCountWidth<0>=0',
      'Project.unit<0>.triggerMatchType<0>=1','Project.unit<0>.triggerPortIsData<0>=true',
      'Project.unit<0>.triggerPortWidth<0>=26']
    fic=output/'coremark_tcm26.fic';fic.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    schema=dict(result='REGISTERED_TCM26_SCHEMA',probe_kind='registered_tcm26',samples=512,clock='ui_clk',
      frequency_hz_nominal=100000000,sample_delay_cpu_cycles=1,
      channels=[dict(index=i,name=name,net=net) for i,(name,net) in enumerate(CHANNELS)],
      function_ranges=ranges,elf_sha256=sha(elf.read_bytes()),fic_sha256=sha(fic.read_bytes()),
      retirement='Delayed mem_commit && !pipe_freeze; same CPU event, not WB-valid.',
      scope='PC exact for upper_zero=1 only; otherwise full PC unknown. Low2 bits0 RV32IM. All fields have one common cycle delay. IF flag is pending fetch, not IF issue. No branch/mispredict or WB instruction observation. Continuous512-cycle local windows, not entire CoreMark CPI.')
    (output/'schema.json').write_text(json.dumps(schema,indent=2)+'\n',encoding='utf-8')
    return schema

def validate_binding(schema,fic,elf):
    channels=[dict(index=i,name=name,net=net) for i,(name,net) in enumerate(CHANNELS)]
    if schema.get('probe_kind')!='registered_tcm26' or schema['channels']!=channels or schema['samples']!=512 or schema['clock']!='ui_clk' or schema.get('sample_delay_cpu_cycles')!=1:
        raise ValueError('Unsupported or misaligned registered26 schema')
    if sha(fic)!=schema['fic_sha256'] or sha(elf)!=schema['elf_sha256']:
        raise ValueError('FIC/ELF hash mismatch')
    if elf_functions(elf)!=schema['function_ranges']:raise ValueError('ELF symbol range mismatch')
    if any(not (0<=v['start']<v['end']<=0x10000) for v in schema['function_ranges'].values()):
        raise ValueError('Algorithm outside observed TCM domain')

def analyze(rows,schema,expected):
    if len(rows)!=schema['samples']:raise ValueError('Need exactly one complete512-cycle window')
    ranges=schema['function_ranges'];hits={name:0 for name in ranges};out=[]
    counts={name:0 for name in ['retired','retired_outside_tcm','if_wait','load_use_wait','data_wait','muldiv_wait','pipe_freeze','traps']}
    for i,row in enumerate(rows):
        if set(row)!=set(NAMES) or not all(v in (0,1) for v in row.values()):raise ValueError('Invalid sample channels/bits')
        if row['mem_commit'] and not row['mem_valid']:raise ValueError('Commit without valid MEM')
        if any(row[x] and not row['pipe_freeze'] for x in ['data_wait','muldiv_wait']):raise ValueError('Wait without freeze')
        low=sum(row[f'mem_pc_{b}']<<b for b in range(2,16))
        pc=low if row['mem_pc_upper_zero'] else None
        retired=row['mem_commit'] and not row['pipe_freeze']
        trap=row['trap_enter'] and not row['pipe_freeze']
        name=next((name for name,v in ranges.items() if v['start']<=pc<v['end']),None) if row['mem_valid'] and pc is not None else None
        if retired and name:hits[name]+=1
        counts['retired']+=int(retired);counts['retired_outside_tcm']+=int(retired and pc is None);counts['traps']+=int(trap)
        for flag in ['data_wait','muldiv_wait','pipe_freeze']:counts[flag]+=row[flag]
        for flag in ['if_wait','load_use_wait']:counts[flag]+=int(row[flag] and not row['pipe_freeze'])
        out.append(dict(sample=i,cpu_sample_offset_cycles=-1,mem_pc=f'{pc:08x}' if pc is not None else '',
          mem_pc_low16=f'{low:04x}',mem_pc_exact=int(pc is not None),function=name or '',retired=int(retired),**row))
    if not counts['retired']:raise ValueError('No useful retirement')
    if counts['traps']:raise ValueError('Trap in algorithm window')
    if hits.get(expected,0)==0:raise ValueError('Expected algorithm has no exact-domain retirement')
    return dict(result='REGISTERED_TCM26_WINDOW_PASS',cycles=len(rows),counts=counts,function_retired=hits,
      local_cpi=len(rows)/counts['retired'],expected_function=expected,sample_delay_cpu_cycles=1,
      stall_fractions_overlapping={x:counts[x]/len(rows) for x in ['if_wait','load_use_wait','data_wait','muldiv_wait','pipe_freeze']},
      scope=schema['scope']),out

def capture_plan(schema,fic,elf,output):
    validate_binding(schema,fic.read_bytes(),elf.read_bytes());output.mkdir(parents=True,exist_ok=False);plans=[]
    for name,v in schema['function_ranges'].items():
        bits=['X']*26
        for i,label in enumerate(NAMES):
            if label.startswith('mem_pc_') and label!='mem_pc_upper_zero':bits[i]=str((v['start']>>int(label[7:]))&1)
            if label in ['mem_pc_upper_zero','mem_valid','mem_commit']:bits[i]='1'
            if label=='pipe_freeze':bits[i]='0'
        pattern=''.join(reversed(bits));d=output/name;d.mkdir()
        commands=['dbg_connect -ip 127.0.0.1 -port 65420','dbg_scan_chain',
          f'dbg_import_fic -file {{{fic.resolve().as_posix()}}}','dbg_set_cur_core -device 0 -core 0',
          'dbg_list','dbg_read_status_register','dbg_add_all_to_waveform','dbg_add_all_to_listing',
          f'dbg_set_unit -unit 0 -func "==" -value {pattern} -radix 2','dbg_set_unit',
          'dbg_set_condition -select 0 -set TU0','dbg_set_condition -active 0','dbg_set_condition',
          'dbg_set_capture -type 0 -windows 1 -position 1','dbg_set_capture','dbg_run','dbg_delay -time 20',
          f'dbg_save_project -file {{{(d/"capture.dprj").resolve().as_posix()}}}','dbg_disconnect','dbg_close']
        script=d/'capture.tcl';script.write_text('\n'.join(commands)+'\n',encoding='utf-8')
        plans.append(dict(function=name,entry_pc=f'{v["start"]:08x}',trigger_binary_msb_first=pattern,
          script=script.as_posix(),script_sha256=sha(script.read_bytes())))
    result=dict(result='PLAN_ONLY_NOT_EXECUTED',plans=plans,clock='ui_clk',samples=512,sample_delay_cpu_cycles=1,
      fic_sha256=sha(fic.read_bytes()),elf_sha256=sha(elf.read_bytes()),
      gate='All physical gates before download; verify TU readback and raw WDF, valid>=10s CoreMark CRC. Restore current formal A61+A55 after diagnosis; startup signals are not this evidence.')
    (output/'plan.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');return result

def main():
    ap=argparse.ArgumentParser(description=__doc__);sp=ap.add_subparsers(dest='command',required=True)
    p=sp.add_parser('prepare');p.add_argument('--adf',type=Path,required=True);p.add_argument('--elf',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    for command in ['plan','decode']:
        p=sp.add_parser(command)
        for arg in ['schema','fic','elf','output']:p.add_argument('--'+arg,type=Path,required=True)
        if command=='decode':p.add_argument('--capture',type=Path,required=True);p.add_argument('--expected',choices=FUNCTIONS,required=True)
    a=ap.parse_args()
    if a.command=='prepare':result=prepare(a.adf,a.elf,a.output)
    else:
        schema=json.loads(a.schema.read_text(encoding='utf-8'));validate_binding(schema,a.fic.read_bytes(),a.elf.read_bytes())
        if a.command=='plan':result=capture_plan(schema,a.fic,a.elf,a.output)
        else:
            raw=a.capture.read_bytes();result,rows=analyze(read_wdf(raw,schema),schema,a.expected)
            result.update(capture_sha256=sha(raw),schema_sha256=sha(a.schema.read_bytes()),fic_sha256=sha(a.fic.read_bytes()),elf_sha256=sha(a.elf.read_bytes()))
            a.output.mkdir(parents=True,exist_ok=False);(a.output/'summary.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
            with (a.output/'samples.csv').open('w',newline='',encoding='utf-8') as f:
                writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
