#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Real DEX + two dependent Android ELFs; no proprietary APK or crash fixture."""
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile

root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'scripts'))
from build_java_framework import toolchain, jar_classes
spec=importlib.util.spec_from_file_location('fixture',root/'scripts/build_macos_fixture.py')
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
ndk=sorted((Path.home()/'Library/Android/sdk/ndk').glob('*/toolchains/llvm/prebuilt/darwin-*/bin'),reverse=True)
cc=fixture.tool('ELF_CC',['/opt/homebrew/opt/llvm/bin/clang',*[p/'clang' for p in ndk]])
ld=fixture.tool('ELF_LD',['ld.lld',*[p/'ld.lld' for p in ndk],'/opt/homebrew/opt/llvm/bin/ld.lld'])
for name,source in [('bootstrap','native_bootstrap.c'),('native_fixture','java_nativeactivity.c')]:
    obj=out/(name+'.o');lib=out/('lib'+name+'.so')
    subprocess.run([cc,'--target=aarch64-linux-android29','-O2','-fPIC','-ffreestanding','-fno-stack-protector','-mno-outline-atomics',
        '-I',root/'src/translation-layer-next','-c',root/'tests/macos/fixture'/source,'-o',obj],check=True)
    subprocess.run([ld,'-shared','--no-relax','--hash-style=gnu','-z','max-page-size=16384','-soname',lib.name,obj,
        *(['-L',out,'-lbootstrap'] if name=='native_fixture' else []),'-o',lib],check=True)
jdk,d8,_=toolchain()
sdk=Path(os.environ.get('ANDROID_SDK_ROOT',os.environ.get('ANDROID_HOME',str(Path.home()/'Library/Android/sdk'))))
android=Path(os.environ['ANDROID_JAR']) if 'ANDROID_JAR' in os.environ else sorted((sdk/'platforms').glob('android-*/android.jar'),reverse=True)[0]
subprocess.run([jdk/'bin/javac','--release','8','-cp',android,'-d',out/'classes',*sorted((root/'tests/macos/java/nativeactivity').glob('*.java'))],check=True)
jar_classes(out/'classes',out/'classes.jar')
subprocess.run([jdk/'bin/java','-cp',d8,'com.android.tools.r8.D8','--min-api','26','--lib',android,'--output',out,out/'classes.jar'],check=True)
strings=['manifest','package','org.husk.nativeboot','application','activity','name','org.husk.nativeboot.Game',
    'intent-filter','action','android.intent.action.MAIN','category','android.intent.category.LAUNCHER',
    'http://schemas.android.com/apk/res/android','org.husk.nativeboot.Bootstrap','provider','org.husk.nativeboot.Provider',
    'authorities','org.husk.nativeboot.provider','meta-data','value','android.app.lib_name','native_fixture','split','config.arm64_v8a','versionCode']
raw=b'';offsets=[]
for s in strings:
    offsets.append(len(raw));b=s.encode();raw+=bytes([len(s),len(b)])+b+b'\0'
raw+=b'\0'*(-len(raw)%4);start=28+4*len(strings)
pool=struct.pack('<HHIIIIII',1,28,start+len(raw),len(strings),0,0x100,start,0)+b''.join(struct.pack('<I',x) for x in offsets)+raw
def begin(name,attrs=()):
    data=b''.join(struct.pack('<IIIHBBI',0xffffffff if k in ('package','split') else 12,strings.index(k),0xffffffff if isinstance(v,int) else strings.index(v),8,0,0x10 if isinstance(v,int) else 3,v if isinstance(v,int) else strings.index(v)) for k,v in attrs)
    return struct.pack('<HHIII',0x102,16,36+len(data),1,0xffffffff)+struct.pack('<IIHHHHHH',0xffffffff,strings.index(name),20,20,len(attrs),0,0,0)+data
def end(name):return struct.pack('<HHIIIII',0x103,16,24,1,0xffffffff,0xffffffff,strings.index(name))
body=pool+begin('manifest',[('package','org.husk.nativeboot'),('versionCode',1)])+begin('application',[('name','org.husk.nativeboot.Bootstrap')])
body+=begin('provider',[('name','org.husk.nativeboot.Provider'),('authorities','org.husk.nativeboot.provider')])+end('provider')
body+=begin('activity',[('name','org.husk.nativeboot.Game')])+begin('meta-data',[('name','android.app.lib_name'),('value','native_fixture')])+end('meta-data')
body+=begin('intent-filter')+begin('action',[('name','android.intent.action.MAIN')])+end('action')+begin('category',[('name','android.intent.category.LAUNCHER')])+end('category')
body+=end('intent-filter')+end('activity')+end('application')+end('manifest')
with zipfile.ZipFile(out/'Startup.apk','w') as z:
    z.writestr('AndroidManifest.xml',struct.pack('<HHI',3,8,len(body)+8)+body)
    z.write(out/'classes.dex','classes.dex')
with zipfile.ZipFile(out/'split.apk','w') as z:
    split=pool+begin('manifest',[('package','org.husk.nativeboot'),('versionCode',1),('split','config.arm64_v8a')])+end('manifest')
    z.writestr('AndroidManifest.xml',struct.pack('<HHI',3,8,len(split)+8)+split)
    for name in ['libbootstrap.so','libnative_fixture.so']:z.write(out/name,'lib/arm64-v8a/'+name)
# Bundle import verifies every split's identity and signature just as it does
# for a user installation. Generate a disposable test key, never relax checks.
with tempfile.TemporaryDirectory(prefix='sign-',dir=out) as temporary:
    key=Path(temporary)/'fixture.p12'
    subprocess.run([jdk/'bin/keytool','-genkeypair','-keystore',key,'-storepass','fixture-only','-alias','fixture',
        '-keyalg','RSA','-keysize','2048','-dname','CN=Husk NativeActivity Test','-validity','3650'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    for name in ['Startup.apk','split.apk']:
        subprocess.run([jdk/'bin/java','-jar',d8.parent/'apksigner.jar','sign','--ks',key,'--ks-pass','pass:fixture-only',
            '--min-sdk-version','26','--v1-signing-enabled','false','--v2-signing-enabled','true',
            '--v3-signing-enabled','true','--v4-signing-enabled','false',out/name],check=True)
with zipfile.ZipFile(out/'Startup.apks','w') as z:
    z.write(out/'Startup.apk','base.apk');z.write(out/'split.apk','split_config.arm64_v8a.apk')
print('Prepared Java NativeActivity initialization fixture')
