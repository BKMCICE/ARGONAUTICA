"""Build the frozen current demo application or Flash boot ROM, without devices.

Default: validate source identities and report the recipe, without compiling.
Use --output NEW_DIRECTORY and --toolchain TOOLCHAIN_ROOT_OR_BIN for a build.
--build is an optional explicit action; --check always stays read-only.
Only source/output locations are parameterized; accepted flags/order stay fixed.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, os, shutil, subprocess, sys

sys.dont_write_bytecode = True
D = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def source_check():
    manifest = json.loads((D.parent / 'provenance.json').read_text(encoding='utf-8'))
    checked = 0
    for name, row in manifest['files'].items():
        if not name.startswith('software/'):
            continue
        path = D.parent / name
        require(path.stat().st_size == row['bytes'] and sha(path) == row['sha256'],
                'Frozen source bytes differ: ' + name)
        checked += 1
    return checked


def compiler(root):
    suffix = '.exe' if os.name == 'nt' else ''
    if root:
        # Preserve a user-selected ASCII junction/symlink spelling. Expanding a
        # Windows toolchain junction into a non-ASCII installation path can
        # make the vendor GCC linker unable to open its own libgcc archive.
        location = Path(os.path.abspath(root))
        if location.is_file():
            gcc = location
        elif (location / ('riscv-none-elf-gcc' + suffix)).is_file():
            gcc = location / ('riscv-none-elf-gcc' + suffix)
        else:
            gcc = location / 'bin' / ('riscv-none-elf-gcc' + suffix)
    else:
        name = shutil.which('riscv-none-elf-gcc')
        require(name is not None, 'Pass --toolchain, or put riscv-none-elf-gcc on PATH')
        gcc = Path(os.path.abspath(name))
    require(gcc.is_file(), 'Missing selected RISC-V compiler')
    objcopy = gcc.with_name('riscv-none-elf-objcopy' + suffix)
    require(objcopy.is_file(), 'Missing objcopy next to selected GCC')
    return gcc, objcopy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--build', action='store_true')
    action.add_argument('--check', action='store_true')
    parser.add_argument('--component', choices=('app', 'boot'), default='app')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--toolchain', type=Path)
    args = parser.parse_args()
    checked = source_check()
    recipe = json.loads((D / ('recipe_' + args.component + '.json')).read_text())
    if args.check or not (args.build or args.output is not None):
        print(json.dumps(dict(result='DEMO_SOURCE_CHECK_PASS_NOT_BUILT', component=args.component,
                              source_files=checked, accepted_bin_sha256=recipe['accepted_bin_sha256'])))
        return
    require(args.output is not None, '--output NEW_DIRECTORY is required for compilation')
    output = args.output.resolve()
    require(not output.exists(), 'Never overwrite an existing build directory')
    gcc, objcopy = compiler(args.toolchain)
    cwd = (D / recipe['cwd']).resolve()
    output.mkdir(parents=True)
    (output / 'tmp').mkdir()
    env = os.environ.copy()
    env.update(TEMP=str(output / 'tmp'), TMP=str(output / 'tmp'), PYTHONDONTWRITEBYTECODE='1')
    result = dict(result='DEMO_BUILD_FAILED', component=args.component, hardware='NOT_RUN',
                  expected_bin_sha256=recipe['accepted_bin_sha256'], source_files_checked=checked,
                  recipe_sha256=sha(D / ('recipe_' + args.component + '.json')),
                  builder_sha256=sha(Path(__file__)), commands=[])
    def save():
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    def run(argv):
        proc = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, timeout=180)
        number = len(result['commands'])
        (output / ('command_' + str(number) + '.log')).write_bytes(proc.stdout + proc.stderr)
        result['commands'].append(dict(argv=argv, exit_code=proc.returncode))
        save()
        require(proc.returncode == 0, 'Compiler command failed; inspect command_' + str(number) + '.log')
        return proc.stdout.decode('utf-8', errors='replace').strip()
    save()
    try:
        result['compiler_version'] = run([str(gcc), '-dumpfullversion'])
        reported_library = run([str(gcc), '-march=rv32im_zicsr', '-mabi=ilp32', '-print-libgcc-file-name'])
        # XPack reports its fully expanded install path even when launched via
        # an ASCII alias. Prefer the exact selected 15.2 multilib under that
        # alias, matching the accepted build's explicit libgcc input.
        selected_library = (gcc.parent.parent / 'lib/gcc/riscv-none-elf' /
                            result['compiler_version'] / 'rv32im/ilp32/libgcc.a')
        library = selected_library.as_posix() if selected_library.is_file() else reported_library
        require(Path(library).is_file(), 'Selected GCC did not resolve libgcc.a')
        # Relative paths keep model_data.S .incbin semantics and avoid embedding
        # machine-specific source prefixes in the maintainable recipe.
        substitutions = {
            '@SOFTWARE@': os.path.relpath(D, cwd).replace('\\', '/'),
            '@OUTPUT@': os.path.relpath(output, cwd).replace('\\', '/'),
            '@LIBGCC@': library.replace('\\', '/'),
        }
        argv = []
        for token in recipe['argv_after_compiler']:
            for old, new in substitutions.items():
                token = token.replace(old, new)
            argv.append(token)
        require(not any('@SOFTWARE@' in x or '@OUTPUT@' in x or '@LIBGCC@' in x for x in argv),
                'Unresolved portable recipe placeholder')
        run([str(gcc), *argv])
        stem = recipe['output_name']
        run([str(objcopy), '-O', 'binary',
             os.path.relpath(output / (stem + '.elf'), cwd),
             os.path.relpath(output / (stem + '.bin'), cwd)])
        binary = output / (stem + '.bin')
        result.update(binary_bytes=binary.stat().st_size, binary_sha256=sha(binary),
                      accepted_binary_exact_match=sha(binary) == recipe['accepted_bin_sha256'])
        if args.component == 'app':
            checker = module(D / 'source_snapshot/tools/check_tcm_image.py', '_current_demo_tcm')
            result['tcm'] = checker.check(output / 'integrated.elf', binary,
                                         D / 'source_snapshot/models/yolo_fastest_1_1', tcm_stack=True)
            require(result['tcm']['text_bytes'] <= 24576, 'TCM code exceeds its reserved range')
        else:
            data = binary.read_bytes()
            require(len(data) <= 65536, 'Boot ROM image exceeds 64 KiB')
            data += b'\0' * ((-len(data)) % 4)
            words = [f'{int.from_bytes(data[n:n+4], "little"):08x}' for n in range(0, len(data), 4)]
            words += ['00000013'] * (16384 - len(words))
            rom = output / 'boot_ram.hex'
            # The accepted PDS ROM is the Windows-generated CRLF text file;
            # choose those bytes explicitly so hosts reproduce its exact SHA.
            rom.write_bytes(('\r\n'.join(words) + '\r\n').encode('ascii'))
            result.update(rom_sha256=sha(rom), accepted_rom_exact_match=sha(rom) ==
                          '50F9A748FF71AE3F3BE75F1593930A87B0CBE98AA90F3BD28A938279C4F9C449')
            require(result['accepted_rom_exact_match'], 'Rebuilt boot ROM differs from accepted ROM')
        require(result['accepted_binary_exact_match'], 'Rebuilt BIN differs from accepted image; not board-qualified')
        result['result'] = 'DEMO_PORTABLE_BUILD_ACCEPTED_BINARY_EXACT_MATCH_NOT_BOARD_RETEST'
        result['scope'] = 'Offline compiler/flat BIN identity and memory checks only; no new device, PDS or board test.'
    except Exception as exc:
        result['error'] = repr(exc)
        save()
        raise
    save()
    print(json.dumps({k: result.get(k) for k in ('result', 'component', 'binary_bytes', 'binary_sha256',
                                                'accepted_binary_exact_match', 'rom_sha256')}, indent=2))


if __name__ == '__main__':
    main()
