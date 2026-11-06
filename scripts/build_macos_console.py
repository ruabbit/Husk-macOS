#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build the pinned PS4/FEX dependency in build/macos; never installs it in Product.

The real core has no complete guest-worker/storage-close contract yet. This
builder makes that work reproducible without advertising a playable runtime.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / 'dependencies/macos-console.lock.json').read_text())
CACHE = ROOT / 'third_party/build/macos'
OUT = ROOT / 'build/macos/Console'
LOGS = ROOT / 'build/logs'
LATCH = LOGS / 'current-macos-runner-fault.json'


def run(args, cwd=ROOT, log=None, test=False):
    args = [str(a) for a in args]
    if test and LATCH.exists():
        raise RuntimeError(f'Validation stopped: inspect {LATCH}')
    try:
        result = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                                timeout=60 if test else None)
    except subprocess.TimeoutExpired as error:
        if log:
            output = (error.stdout or b'') + (error.stderr or b'')
            (LOGS / log).write_bytes(output if isinstance(output, bytes) else output.encode())
        LATCH.write_text(json.dumps({'executable': args[0], 'reason': 'validation-timeout',
                                    'log': log, 'source': 'console-dependency-validation'}, indent=2)+'\n')
        raise RuntimeError(f'Console validation timed out; inspect {LATCH}') from error
    if log:
        (LOGS / log).write_text(result.stdout + result.stderr)
    if test and (result.returncode < 0 or 128 <= result.returncode <= 192):
        LATCH.write_text(json.dumps({'executable': args[0], 'exit': result.returncode,
                                    'log': log, 'source': 'console-dependency-validation'}, indent=2)+'\n')
    if result.returncode:
        raise RuntimeError(f'{args[:3]} exited {result.returncode}\n{(result.stdout + result.stderr)[-5000:]}')
    return result.stdout


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checkout(name, spec, fetch):
    path = CACHE / name
    if not (path / '.git').exists():
        if not fetch:
            raise RuntimeError(f'Missing {path}; use --fetch')
        run(['git', 'clone', '--filter=blob:none', '--no-checkout', spec['repository'], path])
        if spec.get('subdirectory'):
            run(['git', 'sparse-checkout', 'set', spec['subdirectory']], cwd=path)
        run(['git', 'checkout', '--detach', spec['commit']], cwd=path)
    if run(['git', 'rev-parse', 'HEAD'], cwd=path).strip() != spec['commit']:
        raise RuntimeError(f'Refusing to replace a different checkout at {path}')
    if 'submodules' in spec:
        top = [p for p in spec['submodules'] if p.count('/') == 1 or p.startswith('runtime/sources/')]
        if fetch:
            run(['git', 'submodule', 'update', '--init', '--recursive', '--depth', '1', '--', *top], cwd=path,
                log='current-ps4-submodules.log')
        for rel, revision in spec['submodules'].items():
            if not (path / rel / '.git').exists():
                raise RuntimeError(f'Missing submodule {rel}')
            if run(['git', 'rev-parse', 'HEAD'], cwd=path/rel).strip() != revision:
                raise RuntimeError(f'Submodule differs from lock: {rel}')
    if 'patch' in spec:
        patch = ROOT / spec['patch']
        reverse = subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=path,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if reverse.returncode:
            if run(['git', 'status', '--porcelain'], cwd=path).strip():
                raise RuntimeError(f'{name} has unrelated changes; refusing to patch')
            run(['git', 'apply', '--check', patch], cwd=path)
            run(['git', 'apply', patch], cwd=path)
    return path


def configure(source, build, flags, log):
    run(['cmake', '-S', source, '-B', build, '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
         '-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0', *flags], log=log)


def build(fetch, jobs):
    core = checkout('aetherps4', LOCK['core'], fetch)
    fex = checkout('fex-snapshot', LOCK['fex'], fetch) / LOCK['fex']['subdirectory']
    configure(fex, OUT/'FEX', [
        '-DCMAKE_SYSTEM_PROCESSOR=arm64', '-DBUILD_FEXCORE_ONLY=ON', '-DBUILD_FEXCORE_SMOKE=OFF',
        '-DBUILD_FEXCONFIG=OFF', '-DBUILD_TESTING=OFF', '-DBUILD_THUNKS=OFF', '-DENABLE_LTO=OFF',
        '-DENABLE_CCACHE=ON', '-DENABLE_ASSERTIONS=OFF', '-DENABLE_JEMALLOC_GLIBC_ALLOC=OFF',
        '-DENABLE_OFFLINE_TELEMETRY=OFF', '-DENABLE_FEX_ALLOCATOR=OFF', '-DTUNE_ARCH=generic', '-DTUNE_CPU=none',
        '-DCMAKE_CXX_FLAGS=-DFEX_MAC_PHONE_PATH=1 -DFEX_REQUIRE_JIT_HOST=1 -DMETA_NO_STD_FORWARD_DECLARATIONS',
        '-DCMAKE_DISABLE_FIND_PACKAGE_fmt=ON', '-DCMAKE_DISABLE_FIND_PACKAGE_range-v3=ON'], 'current-ps4-recipe-fex-configure.log')
    run(['cmake', '--build', OUT/'FEX', '--parallel', jobs, '--target',
         'FEXCore', 'Common', 'CommonTools', 'JemallocLibs'], log='current-ps4-recipe-fex-build.log')
    archive = OUT/'Core/externals'/LOCK['ffmpeg']['archive']
    if not archive.exists():
        if not fetch:
            raise RuntimeError('Missing FFmpeg archive; use --fetch')
        archive.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(LOCK['ffmpeg']['url'], timeout=90) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != LOCK['ffmpeg']['sha256']:
            raise RuntimeError('FFmpeg download checksum mismatch')
        archive.write_bytes(data)
    if digest(archive) != LOCK['ffmpeg']['sha256']:
        raise RuntimeError('FFmpeg archive checksum mismatch; cache left untouched')
    configure(core, OUT/'Core', [
        '-DENABLE_FEX_GUEST_CPU=ON', '-DENABLE_SHADPS4_IOS_LIB=ON', '-DENABLE_HUSK_MODULE=ON',
        '-DAETHER_MAC_PHONE_PATH=ON', '-DENABLE_DISCORD_RPC=OFF', '-DENABLE_UPDATER=OFF',
        '-DENABLE_SYSTEM_VULKAN=ON', '-DENABLE_SYSTEM_LIBRARIES=OFF', '-DCMAKE_DISABLE_FIND_PACKAGE_fmt=ON',
        '-DALSOFT_BACKEND_JACK=OFF', '-DALSOFT_BACKEND_PORTAUDIO=OFF', '-DALSOFT_BACKEND_PIPEWIRE=OFF',
        '-DALSOFT_BACKEND_PULSEAUDIO=OFF', '-DALSOFT_RTKIT=OFF',
        f'-DHUSK_STORAGE_VALIDATION_SOURCE={ROOT / "tests/macos/console/Storage.cpp"}',
        f'-DFEXCORE_GUEST_CPU_BUILD_DIR={OUT / "FEX"}', f'-DFEXCORE_GUEST_CPU_SOURCE_DIR={fex}'],
        'current-ps4-recipe-core-configure.log')
    run(['cmake', '--build', OUT/'Core', '--target', 'huskps4', 'husk_storage_validation', '--parallel', jobs], log='current-ps4-recipe-core-build.log')


def verify():
    module = OUT/'Core/libhuskps4.dylib'
    for name, spec in [('aetherps4', LOCK['core']), ('fex-snapshot', LOCK['fex'])]:
        if run(['git', 'rev-parse', 'HEAD'], cwd=CACHE/name).strip() != spec['commit']:
            raise RuntimeError(f'Console source revision differs: {name}')
    for name, spec in [('aetherps4', LOCK['core']), ('fex-snapshot', LOCK['fex'])]:
        actual_patch = run(['git', 'diff', '--binary'], cwd=CACHE/name)
        if actual_patch != (ROOT/spec['patch']).read_text():
            raise RuntimeError(f'{name} worktree differs from the recorded patch')
    for rel, revision in LOCK['core']['submodules'].items():
        source = CACHE/'aetherps4'/rel
        if run(['git', 'rev-parse', 'HEAD'], cwd=source).strip() != revision:
            raise RuntimeError(f'Console submodule differs from lock: {rel}')
        if run(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=source).strip():
            raise RuntimeError(f'Console submodule has unrecorded modifications: {rel}')
    core_flags = (OUT/'Core/build.ninja').read_text()
    fex_flags = (OUT/'FEX/build.ninja').read_text()
    if '-DAETHER_FEX_HAS_JIT_HOST=1' not in core_flags or '-DFEX_REQUIRE_JIT_HOST=1' not in fex_flags:
        raise RuntimeError('Console build does not require the Husk JIT host')
    if run(['lipo', '-archs', module]).strip() != 'arm64':
        raise RuntimeError('Console module is not arm64')
    if run(['nm', '-gjU', module]).split() != ['_husk_console_module_v1']:
        raise RuntimeError('Console module export list differs')
    linked = [line.strip().split(' (')[0] for line in run(['otool', '-L', module]).splitlines()[1:]]
    for lib in linked:
        if lib != '@rpath/libhuskps4.dylib' and not lib.startswith(('/usr/lib/', '/System/Library/')):
            raise RuntimeError(f'Uncontained runtime dependency: {lib}')
    imports = run(['nm', '-u', module])
    if any(s in imports for s in ('BreakpointJIT', 'StikDebug', 'BreakGetJIT')):
        raise RuntimeError('Mac module requires an iOS debugger')
    run(['codesign', '--verify', '--strict', module])
    result = {'core': LOCK['core']['commit'], 'fex': LOCK['fex']['commit'], 'module': str(module.relative_to(ROOT)),
              'sha256': digest(module), 'patches': {LOCK[k]['patch']: digest(ROOT/LOCK[k]['patch']) for k in ('core', 'fex')},
              'architecture': 'arm64', 'exports': ['_husk_console_module_v1'], 'dependencies': linked,
              'productEnabled': False, 'releaseBlockers': LOCK['releaseBlockers']}
    (OUT/'dependency-verification.json').write_text(json.dumps(result, indent=2)+'\n')
    print('PASS real arm64 console module, one export, system-only runtime dependencies; not a game compatibility result')


def test():
    target = OUT/'Validation';target.mkdir(exist_ok=True)
    include = ROOT/'src/translation-layer-next'
    fex = CACHE/'fex-snapshot'/LOCK['fex']['subdirectory']
    common = ['-arch', 'arm64', '-mmacosx-version-min=14.0', '-I', include]
    run(['xcrun', 'clang', *common, '-c', include/'husk-jit-arena.c', '-o', target/'arena.o'])
    libraries = [OUT/'FEX/FEXCore/Source/libFEXCore.a', OUT/'FEX/FEXCore/Source/libFEXCore_Base.a', OUT/'FEX/FEXCore/Source/libJemallocLibs.a',
                 OUT/'FEX/External/fmt/libfmt.a']
    run(['xcrun', 'clang++', *common, '-std=c++20', '-DFEX_MAC_PHONE_PATH=1',
         '-I', fex/'FEXCore/include', '-I', fex/'External/fmt/include',
         ROOT/'tests/macos/console/FEXHost.cpp', target/'arena.o', *libraries, '-o', target/'FEXHostTests'])
    run(['xcrun', 'clang', *common, ROOT/'tests/macos/console/ModuleProbe.c', '-o', target/'ModuleProbe'])
    for binary in ('FEXHostTests', 'ModuleProbe'):
        run(['codesign', '--force', '--sign', '-', '--options', 'runtime', '--entitlements',
             ROOT/'src/macos/NativeRunner/NativeRunner.development.entitlements', target/binary])
    for mode in ('valid', 'invalid'):
        run([target/'FEXHostTests', mode], log=f'current-ps4-fex-host-{mode}.log', test=True)
    with tempfile.TemporaryDirectory(prefix='module-', dir=target) as directory:
        fixture=Path(directory)/'invalid.pkg';fixture.write_bytes(bytes(64))
        run([target/'ModuleProbe', OUT/'Core/libhuskps4.dylib', fixture, Path(directory)/'output'],
            log='current-ps4-module-probe.log', test=True)
    with tempfile.TemporaryDirectory(prefix='storage-', dir=target) as directory:
        for mode in ('write', 'read', 'failure'):
            run([OUT/'Core/husk_storage_validation', mode, Path(directory)/('failure' if mode == 'failure' else 'saved')],
                log=f'current-ps4-storage-{mode}.log', test=True)
    print('PASS actual FEX host JIT and real module ABI/refusal; no PS4 game or audio started')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true')
    parser.add_argument('--verify', action='store_true', help='Check the existing module without rebuilding')
    parser.add_argument('--test', action='store_true', help='Run dependency checks without launching a game')
    parser.add_argument('--jobs', default=os.environ.get('HUSK_BUILD_JOBS', '4'))
    args = parser.parse_args()
    LOGS.mkdir(parents=True, exist_ok=True);OUT.mkdir(parents=True, exist_ok=True)
    if not args.verify and not args.test:
        build(args.fetch, args.jobs)
    verify()
    if args.test:
        test()
