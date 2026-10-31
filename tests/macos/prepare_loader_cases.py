#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Two real Android ELF dependency graphs with colliding sonames."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fixture', root/'scripts/build_macos_fixture.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
out = Path(sys.argv[1]).resolve()
ndk = sorted((Path.home()/'Library/Android/sdk/ndk').glob('*/toolchains/llvm/prebuilt/darwin-*/bin'), reverse=True)
cc = fixture.tool('ELF_CC', ['/opt/homebrew/opt/llvm/bin/clang', *[p/'clang' for p in ndk]])
ld = fixture.tool('ELF_LD', ['ld.lld', *[p/'ld.lld' for p in ndk], '/opt/homebrew/opt/llvm/bin/ld.lld'])
# The sibling prefix also checks that system-app is not treated as system/.
for name, origin in [('system-app', 11), ('system', 22)]:
    folder = out/name
    folder.mkdir(parents=True, exist_ok=True)
    for soname, define in [('libcrypto.so', [f'-DPROVIDER_ID={origin}']), ('libclient.so', [])]:
        obj = folder/(soname+'.o')
        subprocess.run([cc, '--target=aarch64-linux-android29', '-O2', '-fPIC', '-ffreestanding',
                        '-fno-stack-protector', *define, '-c', root/'tests/macos/fixture/namespace.c', '-o', obj], check=True)
        subprocess.run([ld, '-shared', '--no-relax', '--hash-style=gnu', '-z', 'max-page-size=16384',
                        '-soname', soname, obj, *([] if define else [folder/'libcrypto.so']), '-o', folder/soname], check=True)
with zipfile.ZipFile(out/'app.apk', 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in ['libcrypto.so', 'libclient.so']:
        archive.write(out/'system-app'/name, 'lib/arm64-v8a/'+name)
for name, go, page in [('go-data', True, 16384), ('mixed-data', False, 4096), ('go-mixed-data', True, 4096), ('mono-data', False, 16384)]:
    obj = out/(name+'.o')
    subprocess.run([cc, '--target=aarch64-linux-android29', '-fPIC', *(['-DGO_DATA'] if go else []), *(['-DMONO_DATA'] if name == 'mono-data' else []),
                    '-c', root/'tests/macos/fixture/data_views.S', '-o', obj], check=True)
    subprocess.run([ld, '-shared', '--no-relax', '--hash-style=gnu', '-z', f'max-page-size={page}', '--eh-frame-hdr', obj, '-o', out/(name+'.so')], check=True)
(out/'ready').write_text('Android ELF namespace and data-view fixtures\n')
