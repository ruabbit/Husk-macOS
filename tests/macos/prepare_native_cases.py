#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
import importlib.util
from pathlib import Path
import subprocess
import sys
import zipfile
import struct
sys.path.insert(0, str(Path(__file__).resolve().parents[2]/"scripts"))
from build_java_framework import toolchain, jar_classes

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fixture', root/'scripts/build_macos_fixture.py')
fixture = importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture)
out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
ndk = sorted((Path.home()/'Library/Android/sdk/ndk').glob('*/toolchains/llvm/prebuilt/darwin-*/bin'), reverse=True)
cc = fixture.tool('ELF_CC', ['/opt/homebrew/opt/llvm/bin/clang', *[p/'clang' for p in ndk]])
ld = fixture.tool('ELF_LD', ['ld.lld', *[p/'ld.lld' for p in ndk], '/opt/homebrew/opt/llvm/bin/ld.lld'])
jdk, d8, _ = toolchain()
java = out/'java/com/rockstargames/oswrapper/GameNative.java'; java.parent.mkdir(parents=True, exist_ok=True)
java.write_text('package com.rockstargames.oswrapper; public class GameNative { public static native void implOnActivityDestroyed(); }')
subprocess.run([jdk/'bin/javac','--release','8','-d',out/'classes',java],check=True)
jar_classes(out/'classes',out/'classes.jar')
subprocess.run([jdk/'bin/java','-cp',d8,'com.android.tools.r8.D8','--min-api','26','--output',out,out/'classes.jar'],check=True)
def manifest():
    strings=['manifest','package','org.husk.driver','application','activity','name','org.libsdl.app.SDLActivity',
             'intent-filter','action','android.intent.action.MAIN','category','android.intent.category.LAUNCHER',
             'http://schemas.android.com/apk/res/android']
    raw=b'';offsets=[]
    for text in strings:
        offsets.append(len(raw));b=text.encode();raw+=bytes([len(text),len(b)])+b+b'\0'
    raw+=b'\0'*(-len(raw)%4);start=28+4*len(strings)
    body=struct.pack('<HHIIIIII',1,28,start+len(raw),len(strings),0,0x100,start,0)+b''.join(struct.pack('<I',x) for x in offsets)+raw
    def begin(name, attrs=()):
        a=b''.join(struct.pack('<IIIHBBI',0xffffffff if k=='package' else 12,strings.index(k),strings.index(v),8,0,3,strings.index(v)) for k,v in attrs)
        return struct.pack('<HHIII',0x102,16,36+len(a),1,0xffffffff)+struct.pack('<IIHHHHHH',0xffffffff,strings.index(name),20,20,len(attrs),0,0,0)+a
    def end(name):return struct.pack('<HHIIIII',0x103,16,24,1,0xffffffff,0xffffffff,strings.index(name))
    body+=begin('manifest',[('package','org.husk.driver')])+begin('application')+begin('activity',[('name','org.libsdl.app.SDLActivity')])+begin('intent-filter')
    body+=begin('action',[('name','android.intent.action.MAIN')])+end('action')+begin('category',[('name','android.intent.category.LAUNCHER')])+end('category')
    body+=end('intent-filter')+end('activity')+end('application')+end('manifest')
    return struct.pack('<HHI',3,8,len(body)+8)+body
for mode in ['normal', 'missing', 'ue4', 'pause-failed', 'godot4']:
    missing = mode == 'missing'
    suffix = '' if mode == 'normal' else '-' + mode
    obj = out/f'driver{suffix}.o'; lib = out/f'driver{suffix}.so'
    subprocess.run([cc, '--target=aarch64-linux-android29', '-O2', '-fPIC', '-ffreestanding', '-fno-stack-protector',
        '-mno-outline-atomics', *(['-DMISSING_DESTROY'] if missing else []), *(['-DACTIVITY_FIXTURE'] if mode == 'ue4' else []), *(['-DPAUSE_FAILURE'] if mode == 'pause-failed' else []), *(['-DGODOT4'] if mode == 'godot4' else []), '-c', root/'tests/macos/fixture/native_driver.c', '-o', obj], check=True)
    subprocess.run([ld, '-shared', '--no-relax', '--hash-style=gnu', '-z', 'max-page-size=16384', obj, '-o', lib], check=True)
    engines = [('ue4','libUE4.so')] if mode == 'ue4' else [('cocos','libcocos2dcpp.so'), ('godot','libgodot_android.so'), ('gamemaker','libyoyo.so'), ('sdl','libSDL3.so'), ('gta','libGame.so')]
    if mode in ['pause-failed', 'godot4']: engines = [('godot','libgodot_android.so')]
    for name, soname in engines:
        with zipfile.ZipFile(out/f'{name}{suffix if mode != "ue4" else ""}.apk','w') as apk:
            apk.writestr('AndroidManifest.xml',manifest())
            apk.writestr(f'lib/arm64-v8a/{soname}',lib.read_bytes())
            apk.write(out/'classes.dex','classes.dex')
            if name == 'sdl':
                apk.writestr('lib/arm64-v8a/libmain.so',lib.read_bytes())
                apk.writestr('lib/arm64-v8a/libdxvk.so',lib.read_bytes())
            if name == 'gta':
                apk.writestr('lib/arm64-v8a/libopenal.so',lib.read_bytes())
                apk.writestr('lib/arm64-v8a/libVendor_mpg123.so',lib.read_bytes())
            if name == 'ue4': apk.writestr('lib/arm64-v8a/libc++_shared.so',lib.read_bytes())
            if name == 'cocos': apk.writestr('lib/arm64-v8a/libfmod.so',lib.read_bytes())
print('Prepared isolated native driver fixtures')
