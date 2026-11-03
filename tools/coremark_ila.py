"""Prepare and decode scalar PDS CoreMark pipeline probes. No hardware operations.

The probe list observes existing production nets; no RTL is inserted by this tool.
PDS must independently validate/route this changed instrumentation before download.
"""
import argparse
import csv
import hashlib
import json
import re
import struct
from pathlib import Path

CPU = 'u_soc/u_core/'
FLAGS = [
    ('if_inflight', CPU+'if_valid'),
    ('id_valid', CPU+'ifid_valid'),
    ('ex_valid', CPU+'idex_valid'),
    ('mem_valid', CPU+'exmem_valid'),
    ('mem_commit', CPU+'mem_commit'),
    ('pipe_freeze', CPU+'pipe_freeze'),
    ('if_wait', CPU+'if_stall'),
    ('load_use_wait', CPU+'ld_use_stall'),
    ('muldiv_wait', CPU+'muldiv_stall'),
    ('mem_redirect', CPU+'mem_redirect'),
    ('branch_mispred_raw', CPU+'exmem_mispred'),
    ('branch_raw', CPU+'exmem_is_branch'),
    ('branch_taken_raw', CPU+'exmem_taken'),
    ('jalr_mispred_raw', CPU+'mem_jalr_target_miss'),
    ('data_wait', 'u_soc/ev_ds'),
    ('trap_enter', CPU+'trap_enter'),
    ('fetch_skid_valid', CPU+'skid_valid'),
]
CHANNELS = [(f'mem_pc_{i}', CPU+f'exmem_pc[{i}]') for i in range(2,32)] + FLAGS
FUNCTIONS = ('core_list_mergesort','core_bench_matrix','core_state_transition')

def sha(data):
    return hashlib.sha256(data).hexdigest().upper()

def elf_functions(raw):
    if len(raw)<52 or raw[:7] != b'\x7fELF\x01\x01\x01' or struct.unpack_from('<H', raw, 18)[0] != 243:
        raise ValueError('Need little-endian ELF32 RISC-V')
    off=struct.unpack_from('<I',raw,32)[0]
    size,count=struct.unpack_from('<HH',raw,46)
    if size!=40 or not count or off+size*count>len(raw):raise ValueError('Invalid ELF section table')
    sections=[struct.unpack_from('<10I',raw,off+i*size) for i in range(count)]
    functions={}
    for section in sections:
        if section[1]!=2:continue
        if section[6]>=count or section[9]!=16 or section[5]%16 or section[4]+section[5]>len(raw):
            raise ValueError('Invalid ELF symbol table')
        names=sections[section[6]]
        if names[1]!=3 or names[4]+names[5]>len(raw):raise ValueError('Invalid ELF string table')
        strings=raw[names[4]:names[4]+names[5]]
        for pos in range(section[4],section[4]+section[5],section[9]):
            name,value,n,info,other,index=struct.unpack_from('<IIIBBH',raw,pos)
            if info&15!=2 or not n:continue
            if name>=len(strings) or b'\0' not in strings[name:]:raise ValueError('Invalid ELF symbol name')
            text=strings[name:strings.index(b'\0',name)].decode('ascii')
            functions[text]={'start':value,'end':value+n,'bytes':n}
    if any(name not in functions for name in FUNCTIONS):
        raise ValueError('CoreMark algorithm symbols missing')
    return {name:functions[name] for name in FUNCTIONS}

def prepare(adf, elf, output):
    ranges=elf_functions(elf.read_bytes())
    if output.exists():raise FileExistsError(output)
    output.mkdir(parents=True)
    lines=['#Fabric Core Inserter Project File', '#A59 existing-core probes; CPU ui_clk only',
        'Project.type=inserter', f'Project.device.designInputFile={adf.resolve().as_posix()}',
        'Project.device.ScanChain=1','Project.device.UserJtag=0','Project.Architecture=1 1 1 ',
        'Project.unit.dimension=1','Project.unit<0>.clockChannel=ui_clk',
        'Project.unit<0>.clockEdge=Rising','Project.unit<0>.ramType=1',
        'Project.unit<0>.dataDepth=512','Project.unit<0>.dataEqualsTrigger=true',
        'Project.unit<0>.enablePowerOnInitData=false','Project.unit<0>.enableStorageQualification=false',
        'Project.unit<0>.triggerSequencerLevels=1','Project.unit<0>.enableMultiWindow=false',
        'Project.unit<0>.triggerPortCount=1']
    lines += [f'Project.unit<0>.triggerChannel<0><{i}>={net}' for i,(_,net) in enumerate(CHANNELS)]
    lines += ['Project.unit<0>.triggerMatchCount<0>=1','Project.unit<0>.triggerMatchCountWidth<0>=0',
        'Project.unit<0>.triggerMatchType<0>=1','Project.unit<0>.triggerPortIsData<0>=true',
        f'Project.unit<0>.triggerPortWidth<0>={len(CHANNELS)}']
    fic=output/'coremark_pipeline.fic';fic.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    schema=dict(result='COREMARK_PIPELINE_SCHEMA',samples=512,clock='ui_clk',frequency_hz_nominal=100000000,
        channels=[dict(index=i,name=name,net=net) for i,(name,net) in enumerate(CHANNELS)],
        function_ranges=ranges,elf_sha256=sha(elf.read_bytes()),fic_sha256=sha(fic.read_bytes()),
        retirement='mem_commit && !pipe_freeze; exact current ev_instr_retired because mem_adv=!pipe_freeze and mem_stall is included in pipe_freeze',
        scope='PC[1:0] reconstructed0 for aligned RV32IM instructions. mem PC only belongs to valid MEM instructions. if_inflight is a request flag, not IF issue; no WB-valid signal inferred. Local512-cycle window, not full benchmark statistics. Raw stalls overlap.')
    (output/'schema.json').write_text(json.dumps(schema,indent=2)+'\n')
    return schema

def read_wdf(raw, schema):
    columns=[];samples=schema['samples']
    for item in schema['channels']:
        key=item['net'].encode('utf-16-be')
        # A scalar record is identified by both the name and following typed data.
        # Qt QString length is in bytes. Check it so e.g. wready cannot match awready.
        starts=[m.start()+len(key) for m in re.finditer(re.escape(key),raw)
                if m.start()>=4 and struct.unpack_from('>I',raw,m.start()-4)[0]==len(key)]
        records=[]
        for end in starts:
            if end+8>len(raw):continue
            tag,n=struct.unpack_from('>II',raw,end)
            if tag!=3 or n!=samples*2 or end+8+n>len(raw):continue
            bits=raw[end+8:end+8+n].decode('utf-16-be')
            if set(bits)<=set('01xXzZ'):records.append(bits)
        if len(records)!=1:raise ValueError(f'Missing/ambiguous scalar WDF record: {item["net"]}')
        if set(records[0])-set('01'):raise ValueError(f'Unknown sample bits: {item["net"]}')
        columns.append(records[0])
    return [{item['name']:int(col[i]) for item,col in zip(schema['channels'],columns)} for i in range(samples)]

def analyze(rows, ranges, expected=None):
    if not rows:raise ValueError('Empty window')
    result=[];totals=dict(retired=0,branch_events=0,mispredict_events=0,if_wait=0,load_use_wait=0,data_wait=0,muldiv_wait=0,pipe_freeze=0,traps=0)
    hits={name:0 for name in ranges}
    for i,row in enumerate(rows):
        if set(row)!=set(name for name,_ in CHANNELS):raise ValueError('Sample channels do not match probe')
        if not all(v in [0,1] for v in row.values()):raise ValueError('Non-binary sample')
        pc=sum(row[f'mem_pc_{b}']<<b for b in range(2,32))
        if row['mem_commit'] and not row['mem_valid']:raise ValueError('Commit without valid MEM')
        if row['data_wait'] and not row['pipe_freeze']:raise ValueError('Data stall must freeze pipeline')
        if row['muldiv_wait'] and not row['pipe_freeze']:raise ValueError('Muldiv wait must freeze pipeline')
        retired=row['mem_commit'] and not row['pipe_freeze']
        branch=row['mem_valid'] and row['branch_raw'] and not row['muldiv_wait']
        mispred=row['mem_valid'] and (row['branch_mispred_raw'] or row['jalr_mispred_raw']) and not row['muldiv_wait']
        trap=row['trap_enter'] and not row['pipe_freeze']
        name=next((name for name,v in ranges.items() if v['start']<=pc<v['end']),None) if row['mem_valid'] else None
        if retired and name:hits[name]+=1
        totals['retired']+=int(retired);totals['branch_events']+=int(branch);totals['mispredict_events']+=int(mispred);totals['traps']+=int(trap)
        for flag in ['data_wait','muldiv_wait','pipe_freeze']:totals[flag]+=row[flag]
        for flag in ['if_wait','load_use_wait']:totals[flag]+=row[flag] and not row['pipe_freeze']
        result.append(dict(sample=i,mem_pc=f'{pc:08x}',function=name or '',retired=int(retired),branch_event=int(branch),mispredict_event=int(mispred),**row))
    if not totals['retired']:raise ValueError('No retirement; not a useful CoreMark window')
    if totals['traps']:raise ValueError('Trap in diagnostic window')
    if expected is not None and hits.get(expected,0)==0:raise ValueError('Expected algorithm has no valid retirement')
    return dict(result='COREMARK_PIPELINE_WINDOW_PASS',cycles=len(rows),counts=totals,function_retired=hits,
        local_cpi=len(rows)/totals['retired'],stall_fractions_overlapping={k:totals[k]/len(rows) for k in ['if_wait','load_use_wait','data_wait','muldiv_wait','pipe_freeze']},
        expected_function=expected,scope='Derived exact RTL events on one local window. Fractions overlap; no summing into exclusive cycle attribution. Not full CoreMark CPI, not an independent clock measurement.'),result


def validate_binding(schema,fic,elf):
    expected=[dict(index=i,name=name,net=net) for i,(name,net) in enumerate(CHANNELS)]
    if schema['channels']!=expected or schema['samples']!=512 or schema['clock']!='ui_clk':
        raise ValueError('Unsupported probe schema')
    if sha(fic)!=schema['fic_sha256'] or sha(elf)!=schema['elf_sha256']:
        raise ValueError('FIC/ELF hash mismatch')
    if elf_functions(elf)!=schema['function_ranges']:raise ValueError('ELF symbol range mismatch')


def capture_plan(schema,fic,elf,output):
    validate_binding(schema,fic.read_bytes(),elf.read_bytes())
    if output.exists():raise FileExistsError(output)
    output.mkdir(parents=True)
    plans=[]
    for name,v in schema['function_ranges'].items():
        bits=['X']*len(CHANNELS)
        for i,(label,_) in enumerate(CHANNELS):
            if label.startswith('mem_pc_'):bits[i]=str((v['start']>>int(label[7:]))&1)
            if label in ('mem_valid','mem_commit'):bits[i]='1'
            if label=='pipe_freeze':bits[i]='0'
        # Trigger Port channel0 is bit0; Binary radix for TU is2 (not the bus display radix).
        pattern=''.join(reversed(bits))
        d=output/name;d.mkdir()
        commands=['dbg_connect -ip 127.0.0.1 -port 65420','dbg_scan_chain',
            f'dbg_import_fic -file {{{fic.resolve().as_posix()}}}',
            'dbg_set_cur_core -device 0 -core 0','dbg_list','dbg_read_status_register',
            'dbg_add_all_to_waveform','dbg_add_all_to_listing',
            f'dbg_set_unit -unit 0 -func "==" -value {pattern} -radix 2',
            'dbg_set_unit','dbg_set_condition -select 0 -set TU0','dbg_set_condition -active 0',
            'dbg_set_condition','dbg_set_capture -type 0 -windows 1 -position 1','dbg_set_capture',
            'dbg_run','dbg_delay -time 20',
            f'dbg_save_project -file {{{(d/"capture.dprj").resolve().as_posix()}}}',
            'dbg_disconnect','dbg_close']
        script=d/'capture.tcl';script.write_text('\n'.join(commands)+'\n')
        plans.append(dict(function=name,entry_pc=f'{v["start"]:08x}',trigger_binary_msb_first=pattern,
            script=script.resolve().as_posix(),script_sha256=sha(script.read_bytes())))
    result=dict(result='CAPTURE_PLAN_ONLY_NOT_EXECUTED',plans=plans,clock='ui_clk',samples=512,
        capture_style='One contiguous512-cycle window; no storage qualification',
        schema_canonical_sha256=sha(json.dumps(schema,sort_keys=True).encode()),fic_sha256=sha(fic.read_bytes()),elf_sha256=sha(elf.read_bytes()),
        hardware_gate='No hardware action here. Must pass original constraints/all corners/pins/independent TA first. Arm debugger after boot but before UART program upload. Decoder and fresh UART benchmark CRC must both pass. Always restore formal A49+A55 afterwards.')
    (output/'plan.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

def main():
    ap=argparse.ArgumentParser(description=__doc__);sp=ap.add_subparsers(dest='command',required=True)
    p=sp.add_parser('prepare');p.add_argument('--adf',type=Path,required=True);p.add_argument('--elf',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p=sp.add_parser('plan');p.add_argument('--schema',type=Path,required=True);p.add_argument('--fic',type=Path,required=True);p.add_argument('--elf',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p=sp.add_parser('decode');p.add_argument('--schema',type=Path,required=True);p.add_argument('--fic',type=Path,required=True);p.add_argument('--elf',type=Path,required=True);p.add_argument('--capture',type=Path,required=True);p.add_argument('--expected',choices=FUNCTIONS,required=True);p.add_argument('--output',type=Path,required=True)
    a=ap.parse_args()
    if a.command=='prepare':print(json.dumps(prepare(a.adf,a.elf,a.output),indent=2));return
    schema=json.loads(a.schema.read_text());validate_binding(schema,a.fic.read_bytes(),a.elf.read_bytes())
    if a.command=='plan':print(json.dumps(capture_plan(schema,a.fic,a.elf,a.output),indent=2));return
    raw=a.capture.read_bytes();summary,rows=analyze(read_wdf(raw,schema),schema['function_ranges'],a.expected);summary.update(capture_sha256=sha(raw),schema_sha256=sha(a.schema.read_bytes()),elf_sha256=schema['elf_sha256'],fic_sha256=schema['fic_sha256'])
    if a.output.exists():raise FileExistsError(a.output)
    a.output.mkdir(parents=True);(a.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    with (a.output/'samples.csv').open('w',newline='') as out:
        writer=csv.DictWriter(out,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print(json.dumps(summary,indent=2))

if __name__=='__main__':main()
