"""Check IO constraint tables and, optionally, actual post-PNR IO cells.

Export with PDS generate_constraint -device IO -db <PNR> -devmap_db <MAP>
-pcf <applied PCF> -file actual_io.pcf. Such tables may retain original pin
attributes even when actual IO cells moved. For physical verification also
pass --netlist and --site-reference, using a trusted device/package baseline.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path


def check(actual_path, fdc_paths):
    expected = {}
    for path in fdc_paths:
        for port, pin in re.findall(
                r'define_attribute\s+\{p:([^}]+)\}\s+\{PAP_IO_LOC\}\s+\{([^}]+)\}',
                path.read_text(encoding='utf-8')):
            if port in expected and expected[port] != pin:
                raise ValueError(f'Conflicting source pin for {port}')
            expected[port] = pin
    if not expected:
        raise ValueError('No source IO locations found')
    actual = {}
    for port, attributes in re.findall(r'^def_port\s+\{([^}]+)\}\s+([^\r\n]+)',
                                        actual_path.read_text(encoding='utf-8'), re.M):
        match = re.search(r'\bLOC=(\S+)', attributes)
        if match:
            if port in actual and actual[port] != match[1]:
                raise ValueError(f'Conflicting exported pin for {port}')
            actual[port] = match[1]
    differences = [{'port': name, 'expected': expected.get(name), 'actual': actual.get(name)}
                   for name in sorted(expected.keys() | actual.keys())
                   if expected.get(name) != actual.get(name)]
    return {'result': 'FAIL' if differences else 'PASS',
            'scope': 'IO constraint table consistency only; not physical placement or external IO timing',
            'expected_ports': len(expected), 'actual_ports': len(actual),
            'differences': differences,
            'files': {str(p): hashlib.sha256(p.read_bytes()).hexdigest().upper()
                      for p in [actual_path, *fdc_paths]},
            'ports': actual}


def physical_sites(netlist, ports):
    text = netlist.read_text(encoding='utf-8')
    cells = {}
    pattern = (r'\b(V_(?:IBUF|OBUF)[A-Z0-9_]*)\s*/\*.*?\*/\s*#\((.*?)\)'
               r'\s*\\(\S+)\s*\((.*?)\);')
    for kind, parameters, instance, connections in re.findall(pattern, text, re.S):
        standard = re.search(r'\.IOSTANDARD\("([^"]+)"\)', parameters)
        for terminal, signal in re.findall(r'\.(I|O|IO|IB|OB)\s*\(\s*([a-zA-Z_]\w*(?:\[\d+\])?)\s*\)', connections):
            if signal in ports:
                cells.setdefault(signal, []).append({
                    'type': kind, 'site': instance.split('/')[0], 'terminal': terminal,
                    'iostandard': standard[1] if standard else None})
    return {name: sorted(items, key=lambda x: (x['type'], x['site'], x['terminal'])) for name, items in sorted(cells.items())}


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('actual_io', type=Path)
    parser.add_argument('--fdc', type=Path, action='append')
    parser.add_argument('--out', type=Path)
    parser.add_argument('--netlist', type=Path)
    parser.add_argument('--site-reference', type=Path)
    args = parser.parse_args()
    paths = args.fdc or [root / 'constr/pangu50k_ddr.fdc', root / 'constr/pangu50k_hdmi.fdc']
    result = check(args.actual_io, paths)
    if bool(args.netlist) != bool(args.site_reference):
        parser.error('--netlist and --site-reference must be used together')
    if args.netlist:
        reference = json.loads(args.site_reference.read_text(encoding='utf-8'))
        if reference['ports'] != result['ports']:
            raise ValueError('Site reference pin table differs from this design')
        sites = physical_sites(args.netlist, result['ports'])
        differences = [{'port': name, 'expected': reference['sites'].get(name), 'actual': sites.get(name)}
                       for name in sorted(result['ports']) if reference['sites'].get(name) != sites.get(name)]
        result['physical_site_differences'] = differences
        result['physical_ports_found'] = len(sites)
        result['scope'] = 'IO table plus actual post-PNR physical IO cells against trusted PGL50H/FBG484 baseline; not external IO timing'
        result['files'].update({str(p): hashlib.sha256(p.read_bytes()).hexdigest().upper()
                                for p in [args.netlist, args.site_reference]})
        if differences or len(sites) != result['expected_ports']:
            result['result'] = 'FAIL'
    if args.out:
        args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f"PDS_PINS_{result['result']} expected={result['expected_ports']} actual={result['actual_ports']}")
    if result['result'] == 'FAIL':
        print(json.dumps({'table_differences': result['differences'][:8],
                          'physical_differences': result.get('physical_site_differences', [])[:8]}, ensure_ascii=False))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
