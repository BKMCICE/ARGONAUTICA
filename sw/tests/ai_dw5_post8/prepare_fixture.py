"""Use the already verified A50 core/MMIO counter fixture unchanged except names."""
from pathlib import Path
import argparse,subprocess,hashlib
r=Path(__file__).resolve().parents[3];path=r/'sim/tb/tb_ai_block8_post_production_soc.v'
expected=subprocess.check_output(['D:/Git/cmd/git.exe','show','a03d8587bae17a613952db535199eab38c5da107:sim/tb/tb_ai_block8_post_production_soc.v'],cwd=r)
raw=path.read_bytes();assert raw.replace(b'\r\n',b'\n')==expected.replace(b'\r\n',b'\n')
text=raw.decode().replace('\r\n','\n').replace('tb_ai_block8_post_production_soc','tb_ai_dw5_post8_soc').replace('A50_','A54_')
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();target=r/'sim/tb/tb_ai_dw5_post8_soc.v'
if a.check:assert target.read_text()==text
else:target.write_text(text,encoding='ascii',newline='\n')
print('A54_ORIGINAL_COUNTER_FIXTURE_PASS',hashlib.sha256(text.encode()).hexdigest().upper())
