#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build the optional, pinned macOS VM dependency set. Never launches a VM."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / 'dependencies/macos-vm.lock.json').read_text())

def run(args, **kw):
    subprocess.run([str(a) for a in args], check=True, **kw)

def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def download(url, path, expected):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        partial = path.with_suffix(path.suffix + '.part')
        run(['curl', '-fL', '--retry', '3', '-C', '-', '-o', partial, url])
        if digest(partial) != expected:
            raise RuntimeError(f'Hash mismatch: {partial}')
        partial.replace(path)
    if digest(path) != expected:
        raise RuntimeError(f'Hash mismatch: {path}')

def replace(path, old, new):
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'Unexpected source shape: {path}: {old[:70]}')
    path.write_text(text.replace(old, new, 1))

def checkout(src, pin):
    if not src.exists():
        run(['git', 'clone', '--no-checkout', pin['repository'], src])
        run(['git', '-C', src, 'checkout', '--detach', pin['commit']])
    actual = subprocess.check_output(['git', '-C', src, 'rev-parse', 'HEAD'], text=True).strip()
    if actual != pin['commit']:
        raise RuntimeError(f'Wrong checkout at {src}; expected {pin["commit"]}; existing files preserved')

def export_symbols(path, symbols):
    text = path.read_text()
    # Also repair duplicates left by an earlier invocation of this integrator.
    for symbol in sorted(set(symbols)):
        text = re.sub(r'^\s*' + re.escape(symbol) + r';[ \t]*\n', '', text, flags=re.MULTILINE)
    if '{\n' not in text:
        raise RuntimeError(f'Unexpected symbol map: {path}')
    declarations = ''.join('  ' + symbol + ';\n' for symbol in sorted(set(symbols)))
    path.write_text(text.replace('{\n', '{\n' + declarations, 1))

def integrate(q):
    # Reuse only display and PCM bridges. No iOS JIT, migration-blocker waivers,
    # environment-triggered snapshot hacks, or custom restore path on macOS.
    for kind, files in {'ui': ['husk-display', 'husk-display-gl'], 'audio': ['husk-audio']}.items():
        for name in files:
            for ext in ['c', 'h']:
                shutil.copy2(ROOT / f'src/ios-jit/{name}.{ext}', q / kind / f'{name}.{ext}')
    replace(q/'ui/meson.build', 'system_ss.add(files(\n', "system_ss.add(files(\n  'husk-display.c',\n")
    replace(q/'ui/meson.build', "files('shader.c', 'console-gl.c')", "files('shader.c', 'console-gl.c', 'husk-display-gl.c')")
    replace(q/'audio/meson.build', "  'noaudio.c',", "  'husk-audio.c',\n  'noaudio.c',")
    replace(q/'audio/audio_template.h', '    case AUDIODEV_DRIVER_WAV:', '    case AUDIODEV_DRIVER_HUSK:\n        return dev->u.husk.TYPE;\n\n    case AUDIODEV_DRIVER_WAV:')
    replace(q/'audio/audio.c', '        CASE(NONE, none, );', '        CASE(NONE, none, );\n        CASE(HUSK, husk, );')
    replace(q/'qapi/audio.json', "  'data': [ 'none',", "  'data': [ 'none', 'husk',")
    replace(q/'qapi/audio.json', "    'none':      'AudiodevGenericOptions',", "    'none':      'AudiodevGenericOptions',\n    'husk':      'AudiodevGenericOptions',")
    symbols = []
    for name in ['husk-display', 'husk-display-gl', 'husk-audio']:
        symbols += re.findall(r'\b(husk_\w+)\(', (ROOT/f'src/ios-jit/{name}.h').read_text())
    export_symbols(q/'system/qemu.symbols', symbols)

def build(prefix, jobs):
    prefix = prefix.resolve()
    prefix.mkdir(parents=True, exist_ok=True)
    for name, version in LOCK['hostPackages'].items():
        actual = subprocess.check_output(['pkg-config', '--modversion', name], text=True).strip()
        if actual != version:
            raise RuntimeError(f'{name}: expected {version}, found {actual}; review dependency lock')
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    cc = subprocess.check_output(['xcrun', '--find', 'clang'], text=True).strip()
    env = dict(os.environ, MACOSX_DEPLOYMENT_TARGET='14.0', CC=cc, OBJC=cc,
               CFLAGS=f'-arch arm64 -mmacosx-version-min=14.0 -isysroot {sdk} -I{ROOT}/build/macos-deps/include',
               OBJCFLAGS=f'-arch arm64 -mmacosx-version-min=14.0 -isysroot {sdk}',
               PKG_CONFIG_PATH=str(prefix/'lib/pkgconfig'))
    for name in ['epoxy', 'virgl']:
        src = ROOT/f'third_party/gpu/{name}-macos'
        pin = LOCK[name]
        checkout(src, pin)
        if name == 'epoxy':
            # Apply the existing resolver fixes to our own isolated checkout,
            # then use the same ANGLE image on both Darwin target platforms.
            p = src/'src/dispatch_common.c'
            if '[epoxy] NO ENTRY POINT' not in p.read_text():
                run(['patch', '-p1', '-i', ROOT/'patches/husk-epoxy-ios-egl-path.patch'], cwd=src)
            s = p.read_text().replace('#if defined(__APPLE__) && TARGET_OS_IPHONE', '#if defined(__APPLE__)')
            for old in ['EGL.framework/Versions/Current/EGL', 'GLESv1_CM.framework/Versions/Current/GLESv1_CM',
                        'GLESv2.framework/Versions/Current/GLESv2', '/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL']:
                s = s.replace('"'+old+'"', '"@rpath/libANGLE-shared.dylib"')
            p.write_text(s)
            options = ['-Dtests=false', '-Dglx=no', '-Degl=yes', '-Dx11=false']
        else:
            options = ['-Dtests=false', '-Dvtest=false', '-Dcheck-gl-errors=false', '-Dvenus=false',
                       '-Dvulkan-dload=false', '-Dplatforms=egl', '-Drender-server-mode=thread']
        b = prefix/f'build-{name}'
        run(['meson', 'setup', *(['--reconfigure'] if (b/'build.ninja').exists() else []), b, src,
             '--prefix', prefix, '--libdir', 'lib', '--buildtype', 'release',
             '--default-library=static', '-Dc_args='+repr(env['CFLAGS'].split()), *options], env=env)
        run(['ninja', '-C', b, '-j', str(jobs), 'install'], env=env)
    archive = ROOT/'third_party/sources/qemu-10.0.12-utm.tar.xz'
    download(LOCK['qemu']['url'], archive, LOCK['qemu']['sha256'])
    q = ROOT/'third_party/build/macos-qemu-10.0.12'
    if not q.exists():
        q.mkdir(parents=True)
        run(['tar', '-xf', archive, '-C', q, '--strip-components=1'])
    integrate(q)
    b = prefix/'build-qemu'; b.mkdir(exist_ok=True)
    if not (b/'build.ninja').exists():
        run([q/'configure', '--target-list=aarch64-softmmu', '--enable-shared-lib',
             '--enable-hvf', '--enable-tcg', '--enable-opengl', '--enable-virglrenderer', '--enable-slirp',
             '--disable-cocoa', '--disable-sdl', '--disable-gtk', '--disable-vnc', '--disable-spice',
             '--disable-curses', '--disable-curl', '--disable-libusb', '--disable-usb-redir', '--disable-tpm',
             '--disable-docs', '--disable-guest-agent', '--disable-tools', '--disable-png', '--disable-pvg',
             '--disable-debug-info', '--disable-capstone', '--disable-zstd', '--disable-bzip2', '--disable-lzfse',
             '--disable-nettle', '--disable-gnutls', '--disable-gcrypt', '--audio-drv-list=',
             f'--extra-cflags={env["CFLAGS"]}', '--extra-ldflags=-Wl,-headerpad_max_install_names'], cwd=b, env=env)
    run(['ninja', '-C', b, '-j', str(jobs), 'libqemu-aarch64-softmmu.dylib'], env=env)
    lib = prefix/'lib/libqemu-aarch64-softmmu.dylib'
    shutil.copy2(b/lib.name, lib)
    shutil.copy2(ROOT/'dependencies/macos-vm.lock.json', prefix/'lock.json')
    notices = prefix/'Notices'; notices.mkdir(exist_ok=True)
    for name, source in {
        'QEMU-COPYING': q/'COPYING', 'QEMU-COPYING.LIB': q/'COPYING.LIB',
        'epoxy-COPYING': ROOT/'third_party/gpu/epoxy-macos/COPYING',
        'virgl-COPYING': ROOT/'third_party/gpu/virgl-macos/COPYING',
    }.items():
        shutil.copy2(source, notices/name)
    receipt = {'qemu': digest(lib), 'lock': digest(prefix/'lock.json'), 'hostPackages': LOCK['hostPackages'],
               'notices': {p.name: digest(p) for p in sorted(notices.iterdir())},
               'patches': {str(p.relative_to(ROOT)): digest(p) for p in [Path(__file__).resolve(), ROOT/'patches/husk-epoxy-ios-egl-path.patch']}}
    (prefix/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(lib)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, default=ROOT/'build/macos-vm-deps')
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    build(args.prefix, args.jobs)
