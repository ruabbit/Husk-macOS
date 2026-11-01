# SPDX-License-Identifier: GPL-2.0-or-later
from pathlib import Path
import os, subprocess, sys, zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts'))
from build_macos_fixture import tool
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
sdk=Path(os.environ.get('ANDROID_SDK_ROOT',str(Path.home()/'Library/Android/sdk')))
ndk=[]
for candidate in dict.fromkeys([sdk,Path.home()/'Library/Android/sdk']):
    ndk+=sorted((candidate/'ndk').glob('*/toolchains/llvm/prebuilt/darwin-*/bin'),reverse=True)
cc=tool('ELF_CC',['/opt/homebrew/opt/llvm/bin/clang',*[p/'clang' for p in ndk]])
ld=tool('ELF_LD',['ld.lld',*[p/'ld.lld' for p in ndk],'/opt/homebrew/opt/llvm/bin/ld.lld'])
subprocess.run([cc,'--target=armv7a-linux-androideabi21','-c',root/'tests/macos/fixture/arm32.S','-o',out/'arm32.o'],check=True)
subprocess.run([ld,'-shared','--hash-style=sysv','-z','notext','-init','a32_ctor','-soname','libarm32.so',out/'arm32.o','-o',out/'libarm32.so'],check=True)
with zipfile.ZipFile(sys.argv[2]) as source,zipfile.ZipFile(out/'mixed.apk','w') as mixed:
    for name in source.namelist():mixed.writestr(name,source.read(name))
    mixed.write(out/'libarm32.so','lib/armeabi-v7a/libonly32.so')
print('Built controlled ARM32 ELF and mixed ABI fixture')
