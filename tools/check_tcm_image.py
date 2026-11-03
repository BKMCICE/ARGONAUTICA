"""Check ELF execution/load addresses and the flat DDR upload of a TCM build."""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def check(elf_path, bin_path, model_root=None, tcm_stack=False):
    raw = elf_path.read_bytes()
    if raw[:7] != b'\x7fELF\x01\x01\x01' or struct.unpack_from('<H', raw, 18)[0] != 243:
        raise ValueError('Expected a little-endian ELF32 RISC-V executable')
    entry, phoff, shoff = struct.unpack_from('<III', raw, 24)
    phentsize, phnum, shentsize, shnum, strings_index = struct.unpack_from('<HHHHH', raw, 42)
    ph = [struct.unpack_from('<8I', raw, phoff + i*phentsize) for i in range(phnum)]
    sh = [struct.unpack_from('<10I', raw, shoff + i*shentsize) for i in range(shnum)]
    strings = sh[strings_index]
    names = raw[strings[4]:strings[4]+strings[5]]
    name_of = lambda offset: names[offset:].split(b'\0', 1)[0].decode('ascii')
    sections = {name_of(s[0]): s for s in sh}
    symbols = {}
    for s in sh:
        if s[1] != 2:
            continue
        st = sh[s[6]]
        strings = raw[st[4]:st[4]+st[5]]
        for offset in range(s[4], s[4]+s[5], s[9]):
            name, value, size, info, other, index = struct.unpack_from('<IIIBBH', raw, offset)
            symbols[strings[name:].split(b'\0', 1)[0].decode('ascii')] = value
    text = sections['.text']
    start, end = text[3], text[3]+text[5]
    if entry != 0x80000000 or not (0x8000 <= start < end <= 0x10000):
        raise ValueError('Bootstrap entry/text execution range mismatch')
    for name in ['main', 'trap_entry', 'tcm_text_verify']:
        if not start <= symbols[name] < end:
            raise ValueError(f'{name} does not execute from TCM')
    for name in ['.rodata', '.data', '.bss', '.tohost']:
        s = sections[name]
        if not (0x80000000 <= s[3] <= s[3]+s[5] <= 0x81000000):
            raise ValueError(f'{name} is not inside the DDR data window')
    if tcm_stack:
        if (symbols.get('__stack_bottom'),symbols.get('__stack_guard_end'),symbols['__stack_top']) != (0xe000,0xe100,0x10000):
            raise ValueError('Unexpected reserved TCM stack/guard range')
        if end > 0xe000:
            raise ValueError('TCM code overlaps reserved stack')
        for name in ['tcm_stack_begin','tcm_stack_finish']:
            if not start <= symbols.get(name,0) < end:
                raise ValueError('TCM stack runtime checks missing from text')
    elif symbols['__heap_start'] >= symbols['__stack_top']:
        raise ValueError('Static data overlaps the DDR stack')
    pieces = []
    text_load = None
    for name, s in sections.items():
        if s[1] != 1 or not s[2] & 2 or not s[5]:
            continue
        matches = [p for p in ph if p[0] == 1 and p[2] <= s[3] and s[3]+s[5] <= p[2]+p[4]
                   and p[1] <= s[4] and s[4]+s[5] <= p[1]+p[4]]
        if len(matches) != 1:
            raise ValueError(f'Ambiguous/missing load segment for {name}')
        p = matches[0]
        load = p[3] + s[3] - p[2]
        if not 0x80000000 <= load < load+s[5] <= 0x81000000:
            raise ValueError(f'{name} is missing from the DDR upload image')
        pieces.append((load, raw[s[4]:s[4]+s[5]], name))
        if name == '.text':
            text_load = load
    if (symbols['__tcm_text_start'], symbols['__tcm_text_end'], symbols['__tcm_text_load']) != (start, end, text_load):
        raise ValueError('Startup copy symbols disagree with ELF load/execution addresses')
    base = min(load for load, data, name in pieces)
    limit = max(load+len(data) for load, data, name in pieces)
    image = bytearray(limit-base)
    last = base
    for load, data, name in sorted(pieces):
        if load < last:
            raise ValueError(f'Overlapping flat-image section: {name}')
        image[load-base:load-base+len(data)] = data
        last = load+len(data)
    binary = bin_path.read_bytes()
    if base != entry or bytes(image) != binary:
        raise ValueError('Flat binary does not match the ELF physical load image')
    model_checks = {}
    if model_root:
        ro = sections['.rodata']
        for symbol, filename in [('yolo_weights', 'weights_int8.bin'),
                                 ('yolo_params_q24', 'params_q24.bin'),
                                 ('yolo_dog_image', 'dog_chw_int8.bin')]:
            expected = (model_root / filename).read_bytes()
            offset = ro[4] + symbols[symbol] - ro[3]
            if raw[offset:offset+len(expected)] != expected:
                raise ValueError(f'Model bytes changed: {symbol}')
            model_checks[symbol] = hashlib.sha256(expected).hexdigest().upper()
    return dict(result='TCM_IMAGE_PASS', entry=f'{entry:08x}',
                text_start=f'{start:08x}', text_end=f'{end:08x}',
                text_load=f'{text_load:08x}', text_bytes=end-start,
                static_ddr_end=f'{symbols["__heap_start"]:08x}',
                stack_top=f'{symbols["__stack_top"]:08x}',
                image_bytes=len(binary), image_sha256=hashlib.sha256(binary).hexdigest().upper(),
                model_checks=model_checks,
                scope='Offline ELF/flat payload verification. Runtime PC/copy and physical results remain separate.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('elf', type=Path)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--model-root', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--tcm-stack', action='store_true')
    args = parser.parse_args()
    result = check(args.elf, args.binary, args.model_root, args.tcm_stack)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
