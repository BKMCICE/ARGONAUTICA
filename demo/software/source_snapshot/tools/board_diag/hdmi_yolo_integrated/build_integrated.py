"""Compile the private H07 integrated input firmware; no PDS or devices.
The only production-source edits are the input adapter and result/guard callbacks.
Frozen model/operator files and original common startup/runtime sources are copied.
"""
from pathlib import Path
import argparse,datetime,hashlib,importlib.util,json,os,re,subprocess,sys,traceback
sys.dont_write_bytecode=True
R=Path('F:/2026FPGANEXT');D=R/'tools/board_diag/hdmi_yolo_integrated';W=Path('F:/ARGONAUTICA_work/board_tests/20261102_h07_hdmi_yolo')
GCC=Path('F:/rvtools/xpack-riscv-none-elf-gcc-15.2.0-1/bin')
LIB=GCC.parent/'lib/gcc/riscv-none-elf/15.2.0/rv32im/ilp32/libgcc.a'
BASE_SHA='E6D4DC9F76BCD11E645ECE677DC8AE3517116E9F2704502E0A679F8BF55743B5'
FORMAL_SHA='E1755602A44E9A1BF854457EC87C4E18F0F680B3533D2A00F3BD5EC18761BB18'
def need(v,s):
 if not v:raise ValueError(s)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def put(p,v):Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
def load(name,p):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def derive_main(text):
 marker='#if YOLO_UART_IMAGE\nstatic int8_t uart_image[YOLO_INPUT_BYTES];'
 need(text.count(marker)==1,'Exact original UART input block')
 start=text.index(marker);end=text.index('\nstatic int32_t apply_q24',start)
 old=text[start:end]
 new='''#if YOLO_UART_IMAGE
uint32_t h07_chw_guard_low[8] __attribute__((section(".h07_chw_guard_low"),aligned(32)));
int8_t uart_image[YOLO_INPUT_BYTES] __attribute__((section(".h07_chw"),aligned(32)));
uint32_t h07_chw_guard_high[8] __attribute__((section(".h07_chw_guard_high"),aligned(32)));
extern int h07_capture_to_chw(int8_t *,uint32_t);
extern int h07_finish_input(void);
extern int h07_yolo_failure(uint32_t);
static int receive_image(void) { return h07_capture_to_chw(uart_image,YOLO_INPUT_BYTES); }
#else
#error "H07 requires production YOLO_UART_IMAGE input semantics"
#endif
'''
 transformed=text[:start]+new+text[end:]
 i=transformed.index('int main(void)\n{');body=transformed[i:]
 returns=re.findall(r'return ([0-9]+);',body);need(returns.count('0')==1 and returns[-1]=='0','Original unique successful main return')
 newbody=re.sub(r'return ([1-9][0-9]*);',r'return h07_yolo_failure(\1);',body)
 newbody=newbody.replace('return 0;','return h07_finish_input();')
 result=transformed[:i]+newbody
 # Reverse every allowed replacement and demand exact original text.
 reverse=result.replace(new,old,1)
 reverse=re.sub(r'return h07_yolo_failure\(([1-9][0-9]*)\);',r'return \1;',reverse)
 reverse=reverse.replace('return h07_finish_input();','return 0;')
 need(reverse==text,'Unexpected production math/control mutation')
 return result,dict(original_input_block=old,new_input_block=new,main_error_return_codes=returns[:-1],success_return='h07_finish_input',reversible_exact_original=True)

def build(out):
 out=Path(out).resolve();need(out.is_relative_to(W/'build') and out!=(W/'build').resolve(),'Fresh H07 build subdirectory required');out.mkdir(parents=True,exist_ok=False)
 cfgp=R/'docs/current_board_configuration.json';cfg=read(cfgp);need(sha(cfgp)==FORMAL_SHA,'Formal config changed')
 origin=R/'docs/validation/20261025-a97-pool-separable-production/graph/host_summary.json';old=read(origin)
 prod=[R/n for n in old['source_files'] if n.startswith(('sw/common/','sw/yolo_fixed/')) and Path(n).suffix in ('.c','.h','.S')]
 for p in prod:need(sha(p)==old['source_files'][p.relative_to(R).as_posix()],'Frozen A97 source changed '+str(p))
 need(sha(R/'sw/yolo_fixed/main.c')==BASE_SHA,'Original A97 main drift')
 own=[D/n for n in ['pipeline.c','quantize.c','quantize.h','link_integrated.ld','build_integrated.py']]
 model=R/'models/yolo_fastest_1_1';sources=prod+own+[model/n for n in ['weights_int8.bin','params_q24.bin','dog_chw_int8.bin','fixed_manifest.json','activation_scales_2img.json']]+[cfgp,origin,R/'tools/check_tcm_image.py',R/'tools/board_diag/hdmi_frame/contract.py',R/'tools/board_diag/hdmi_frame/capture_layout.h',R/'tools/board_diag/hdmi_model_capture/raw_capture_probe.c']
 sources=list(dict.fromkeys(sources));snap=out/'source_snapshot'
 result=dict(result='H07_INTEGRATED_FIRMWARE_BUILD_FAILED',started_utc=now(),hardware='NOT_RUN',PDS='NOT_RUN',formal_configuration_sha256=FORMAL_SHA,original_A97_main_sha256=BASE_SHA,commands=[],source_bindings={p.relative_to(R).as_posix():sha(p)for p in sources},source_snapshot={},scope='Private firmware compilation only; unchanged Z BIT, original model/operators/thresholds and TCM runtime. No new board inference claim.')
 def save():put(out/'result.json',result)
 save()
 try:
  for p in sources:
   q=snap/p.relative_to(R);q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(p.read_bytes());result['source_snapshot'][q.relative_to(out).as_posix()]=sha(q)
  generated,derivation=derive_main((snap/'sw/yolo_fixed/main.c').read_text());gen=out/'generated';gen.mkdir();main=gen/'main.c';main.write_text(generated,encoding='utf-8',newline='\n');put(gen/'derivation.json',derivation)
  result['generated_files']={p.relative_to(out).as_posix():sha(p)for p in [main,gen/'derivation.json']}
  tmp=out/'tmp';tmp.mkdir();env=os.environ.copy();env.update(TEMP=str(tmp),TMP=str(tmp),PYTHONDONTWRITEBYTECODE='1')
  flags=cfg['firmware']['build_flags'];need(flags['YOLO_UART_IMAGE']==flags['TCM_TEXT']==flags['TCM_STACK']==1,'Original production input/TCM build configuration')
  common=snap/'sw/common';yolo=snap/'sw/yolo_fixed';private=snap/D.relative_to(R);capture=snap/'tools/board_diag/hdmi_frame'
  comp=[str(GCC/'riscv-none-elf-gcc.exe'),'-march=rv32im_zicsr','-mabi=ilp32','-O2','-g','-ffreestanding','-fno-builtin','-nostdlib','-nostartfiles','-Wall','-Wextra','-fno-common','-ffunction-sections','-fdata-sections','-fstack-usage','-DCLK_HZ=100000000','-DBAUD=115200',*[f'-D{k}={v}'for k,v in flags.items()],*[v for p in [common,yolo,private,capture]for v in ['-I',str(p)]],'-Wl,--gc-sections','-Wl,-Map='+str(out/'integrated.map'),'-T',str(private/'link_integrated.ld'),'-o',str(out/'integrated.elf'),*[str(common/n)for n in ['crt0.S','uart.c','tcm_text.c','tcm_stack.c']],str(main),str(yolo/'postprocess.c'),str(yolo/'model_data.S'),str(private/'pipeline.c'),str(private/'quantize.c'),str(LIB)]
  commands=[comp,[str(GCC/'riscv-none-elf-objcopy.exe'),'-O','binary',str(out/'integrated.elf'),str(out/'integrated.bin')],[str(GCC/'riscv-none-elf-readelf.exe'),'-S','-l','-s',str(out/'integrated.elf')],[str(GCC/'riscv-none-elf-objdump.exe'),'-d',str(out/'integrated.elf')]]
  result['CFLAGS']=flags;result['tool_bindings']={str(p):dict(bytes=p.stat().st_size,sha256=sha(p))for p in [Path(sys.executable),LIB,*dict.fromkeys(Path(c[0])for c in commands)]}
  for i,argv in enumerate(commands):
   log=out/f'command_{i}.log';row=dict(command=argv,cwd=str(yolo),started_utc=now(),log=log.name)
   try:
    p=subprocess.run(argv,cwd=yolo,env=env,capture_output=True,timeout=120);log.write_bytes(p.stdout+p.stderr);row.update(exit_code=p.returncode,log_sha256=sha(log),finished_utc=now())
   except subprocess.TimeoutExpired as exc:
    log.write_bytes((exc.stdout or b'')+(exc.stderr or b''));row.update(exit_code=None,timed_out=True,log_sha256=sha(log));result['commands'].append(row);save();raise
   result['commands'].append(row);save();need(row['exit_code']==0,'Native command failed '+str(i))
  helper=load('h07_original_tcm_check',snap/'tools/check_tcm_image.py');tcm=helper.check(out/'integrated.elf',out/'integrated.bin',snap/'models/yolo_fastest_1_1',tcm_stack=True);put(out/'tcm_check.json',tcm)
  contract=load('h07_original_elf_inventory',snap/'tools/board_diag/hdmi_frame/contract.py');sections,symbols=contract.elf_inventory(out/'integrated.elf')
  addr=lambda n:symbols[n]['start'];size=lambda n:symbols[n]['bytes']
  need(addr('h07_chw_guard_low')+32==addr('uart_image') and addr('uart_image')+307200==addr('h07_chw_guard_high'),'Actual adjacent CHW guards')
  need(size('uart_image')==307200 and size('h07_chw_guard_low')==size('h07_chw_guard_high')==32,'Actual guarded CHW object sizes')
  need(addr('__h07_input_start')==addr('uart_image') and addr('__h07_input_end')==addr('h07_chw_guard_high'),'Actual linker input symbols')
  need(addr('__bss_start')<=addr('h07_chw_guard_low')<addr('h07_chw_guard_high')+32<=addr('__bss_end')<=addr('__heap_limit')==0x80400000,'Zeroed static data and CHW wholly below protected RAW')
  need(addr('__capture_frame_start')==0x80400000 and addr('__capture_frame_limit')==0x80a00000,'Full6MiB protected reservation constants')
  for name,row in sections.items():
   if row['bytes'] and row['start']>=0x80000000:need(row['end']<=0x80400000,'Application allocation overlaps RAW '+name)
  for n in ['h07_capture_to_chw','h07_finish_input','h07_yolo_failure','h07_quantize_pixels']:
   need(sections['.ddr_h07']['start']<=addr(n)<sections['.ddr_h07']['end'],'Cold helper outside DDR section '+n)
  stack_files=list(out.rglob('*.su'));stack_rows=[]
  for p in stack_files:
   for line in p.read_text().splitlines():
    f=line.split('\t')
    if len(f)==3:stack_rows.append(dict(function=f[0],bytes=int(f[1]),kind=f[2],report=str(p.relative_to(out))))
  need(stack_rows,'Native stack reports required')
  cold=[x for x in stack_rows if 'pipeline.c:'in x['function'] or 'quantize.c:'in x['function']]
  need(cold and all(x['kind']=='static'for x in cold) and sum(x['bytes']for x in cold)<7936,'Conservative cold helper static frames fit existing guard window')
  legacy_dynamic=[x for x in stack_rows if x['kind']!='static']
  need(all(x['function'].endswith(':conv1x1_input_reuse') and x['bytes']==208 and x['kind']=='dynamic'for x in legacy_dynamic),'Unexpected dynamic stack allocation; original bounded VLA requires independent whole-program audit')
  result.update(result='H07_INTEGRATED_FIRMWARE_BUILD_PASS',tcm=tcm,sections=sections,symbols=symbols,stack_usage={'rows':stack_rows,'cold_helper_frame_sum':sum(x['bytes']for x in cold),'legacy_dynamic':legacy_dynamic,'whole_program_bound':'PENDING_INDEPENDENT_AUDIT','scope':'Conservative sum of new cold helper static frames only; excludes shared callees. Original network bounded VLA retained. Whole-program bound is independent audit; physical stack guards not yet measured.'},stack_report_bindings={str(p.relative_to(out)):sha(p)for p in stack_files},artifacts={n:dict(bytes=(out/n).stat().st_size,sha256=sha(out/n))for n in ['integrated.elf','integrated.bin','integrated.map','tcm_check.json']},input_layout=dict(chw_base=addr('uart_image'),bytes=307200,guard_low=addr('h07_chw_guard_low'),guard_high=addr('h07_chw_guard_high'),raw_base=0x80400000,raw_limit=0x80a00000))
  need(all(sha(R/n)==h for n,h in result['source_bindings'].items()),'Original/source changed during build');need(all(sha(out/n)==h for n,h in result['source_snapshot'].items()),'Snapshot changed')
 except Exception as exc:result.update(result='H07_INTEGRATED_FIRMWARE_BUILD_FAILED',error=repr(exc),traceback=traceback.format_exc())
 result['finished_utc']=now();save();print(json.dumps({k:result.get(k)for k in ['result','error','tcm','input_layout']},ensure_ascii=False));return 0 if result['result']=='H07_INTEGRATED_FIRMWARE_BUILD_PASS'else 1
if __name__=='__main__':
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--build',action='store_true');ap.add_argument('--output',type=Path);a=ap.parse_args()
 if not a.build:print('H07_INTEGRATED_FIRMWARE_NOT_RUN');raise SystemExit(0)
 if a.output is None:ap.error('--build requires --output')
 raise SystemExit(build(a.output))
