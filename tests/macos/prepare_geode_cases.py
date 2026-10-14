#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline Geode cache and Android ELF fixtures; no proprietary game or network."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fixture', root/'scripts/build_macos_fixture.py')
fixture = importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture)
out, native = map(Path, sys.argv[1:])
out.mkdir(parents=True, exist_ok=True)
ndk = sorted((Path.home()/'Library/Android/sdk/ndk').glob('*/toolchains/llvm/prebuilt/darwin-*/bin'), reverse=True)
cc = fixture.tool('ELF_CC', ['/opt/homebrew/opt/llvm/bin/clang', *[p/'clang' for p in ndk]])
ld = fixture.tool('ELF_LD', ['ld.lld', *[p/'ld.lld' for p in ndk], '/opt/homebrew/opt/llvm/bin/ld.lld'])

def manifest():
    strings = ['manifest', 'package', 'com.robtopx.geometryjump', 'versionCode',
               'application', 'http://schemas.android.com/apk/res/android']
    raw = b''; offsets = []
    for s in strings:
        offsets.append(len(raw)); b = s.encode(); raw += bytes([len(s), len(b)]) + b + b'\0'
    raw += b'\0'*(-len(raw)%4); start = 28+4*len(strings)
    body = struct.pack('<HHIIIIII',1,28,start+len(raw),len(strings),0,0x100,start,0)
    body += b''.join(struct.pack('<I',v) for v in offsets)+raw
    attrs = struct.pack('<IIIHBBI',0xffffffff,1,2,8,0,3,2)
    attrs += struct.pack('<IIIHBBI',5,3,0xffffffff,8,0,0x10,39)
    def begin(index, a=b''):
        return struct.pack('<HHIII',0x102,16,36+len(a),1,0xffffffff)+struct.pack('<IIHHHHHH',0xffffffff,index,20,20,len(a)//20,0,0,0)+a
    def end(index): return struct.pack('<HHIIIII',0x103,16,24,1,0xffffffff,0xffffffff,index)
    body += begin(0,attrs)+begin(4)+end(4)+end(0)
    return struct.pack('<HHI',3,8,len(body)+8)+body

def archive(path, entries):
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
        for name, data in entries.items(): z.writestr(name,data)

for mode in ('normal','jni-error'):
    case = out/mode; cache = case/'geode'; cache.mkdir(parents=True, exist_ok=True)
    obj, lib = out/f'{mode}.o', out/f'{mode}.so'
    subprocess.run([cc,'--target=aarch64-linux-android29','-O2','-fPIC','-ffreestanding','-fno-stack-protector',
                    *(['-DJNI_ERROR'] if mode=='jni-error' else []),'-c',root/'tests/macos/fixture/geode.c','-o',obj],check=True)
    subprocess.run([ld,'-shared','--no-relax','--hash-style=gnu','-z','max-page-size=16384',obj,'-o',lib],check=True)
    with zipfile.ZipFile(native/'cocos.apk') as z:
        entries = {name:z.read(name) for name in z.namelist() if name!='AndroidManifest.xml'}
    entries['AndroidManifest.xml'] = manifest()
    archive(case/'game.apk',entries)
    archive(cache/'geode-android64.zip',{'Geode.android64.so':lib.read_bytes()})
    # A distinct ELF without JNI/constructors stands in for the launcher's C++ runtime.
    cpp = out/'cpp.c'; cpp.write_text('int geode_cpp_fixture = 1;\n')
    subprocess.run([cc,'--target=aarch64-linux-android29','-fPIC','-c',cpp,'-o',out/'cpp.o'],check=True)
    subprocess.run([ld,'-shared',out/'cpp.o','-o',out/'cpp.so'],check=True)
    archive(cache/'geode-launcher.apk',{'lib/arm64-v8a/libc++_shared.so':(out/'cpp.so').read_bytes()})
    archive(cache/'geode-resources.zip',{'loader.txt':b'new!'})
    hashes = {name:hashlib.sha256((cache/name).read_bytes()).hexdigest() for name in ('geode-android64.zip','geode-launcher.apk','geode-resources.zip')}
    (cache/'installation.json').write_text(json.dumps(dict(schema=1,version='5.0.0',versionCode=39,
        gameDigest=hashlib.sha256((case/'game.apk').read_bytes()).hexdigest(),files=hashes)))
with zipfile.ZipFile(out/'normal/geode/geode-android64.zip') as z: elf = z.read('Geode.android64.so')
archive(out/'geode4.zip',{'Geode.android64.so':elf,'resources/loader.txt':b'old!'})
archive(out/'traversal.zip',{'Geode.android64.so':elf,'../escape':b'bad'})
(out/'ready').write_text('offline Geode fixtures\n')
print('Prepared offline Geode cache and JNI fixtures')
