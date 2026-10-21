#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build a small real Java APK for lifecycle tests; never imports a user APK."""
from pathlib import Path
import os
import struct
import subprocess
import sys
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'scripts'))
from build_java_framework import toolchain, jar_classes

output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
jdk, d8, _ = toolchain()
sdk = Path(os.environ.get('ANDROID_SDK_ROOT', os.environ.get('ANDROID_HOME', str(Path.home()/'Library/Android/sdk'))))
android = Path(os.environ['ANDROID_JAR']) if 'ANDROID_JAR' in os.environ else next(iter(sorted((sdk/'platforms').glob('android-*/android.jar'), reverse=True)), None)
if not android:
    raise SystemExit('Install an Android SDK platform or set ANDROID_JAR for the lifecycle fixture')
web = len(sys.argv) > 2 and sys.argv[2] == 'web'
keystore = len(sys.argv) > 2 and sys.argv[2] == 'keystore'
source = Path(__file__).parent/('java/WebStorageActivity.java' if web else 'java/KeyStoreActivity.java' if keystore else 'java/LifecycleActivity.java')
sources = [source] if web or keystore else [source, Path(__file__).parent/'java/FrameworkChecks.java', Path(__file__).parent/'java/DocumentChecks.java']
if not web and not keystore:
    sources += [Path(__file__).parent/'java/MissingOptional.java', Path(__file__).parent/'java/unicode/例.java']
subprocess.run([jdk/'bin/javac', '--release', '8', '-cp', android, '-d', output/'classes', *sources], check=True)
if not web and not keystore:
    (output/'classes/missing/optional/MissingOptional.class').unlink()
    (output/'obb').mkdir(exist_ok=True)
    (output/'obb/main.1.org.husk.lifecycle.obb').write_bytes(b'OBB runtime fixture')
jar_classes(output/'classes', output/'classes.jar')
subprocess.run([jdk/'bin/java', '-cp', d8, 'com.android.tools.r8.D8', '--min-api', '26', '--lib', android,
                '--output', output, output/'classes.jar'], check=True)

strings = ['manifest','package','org.husk.lifecycle','application','activity','name','org.husk.lifecycle.LifecycleActivity',
           'intent-filter','action','android.intent.action.MAIN','category','android.intent.category.LAUNCHER',
           'http://schemas.android.com/apk/res/android','uses-feature','glEsVersion']
if web:
    strings[2] = 'org.husk.webstorage'
    strings[6] = 'org.husk.webstorage.WebStorageActivity'
    strings.append('org.husk.webstorage.WebStorageActivity$Child')
if keystore:
    strings[2] = 'org.husk.keystore'
    strings[6] = 'org.husk.keystore.KeyStoreActivity'
le = lambda n: struct.pack('<I',n)
text = b''; offsets = []
for value in strings:
    offsets.append(len(text)); b=value.encode(); text+=bytes([len(value),len(b)])+b+b'\0'
text += b'\0'*(-len(text)%4)
start=28+4*len(strings)
pool=struct.pack('<HHIIIIII',1,28,start+len(text),len(strings),0,0x100,start,0)+b''.join(le(x) for x in offsets)+text
def begin(name, attrs=()):
    data=b''
    for key,kind,value in attrs:
        data+=struct.pack('<IIIHBBI',0xffffffff if key=='package' else 12,strings.index(key),value if kind==3 else 0xffffffff,8,0,kind,value)
    return struct.pack('<HHIII',0x102,16,36+len(data),1,0xffffffff)+struct.pack('<IIHHHHHH',0xffffffff,strings.index(name),20,20,len(attrs),0,0,0)+data
def end(name): return struct.pack('<HHIIIII',0x103,16,24,1,0xffffffff,0xffffffff,strings.index(name))
body=pool+begin('manifest',[('package',3,2)])+begin('uses-feature',[('glEsVersion',0x11,0x20000)])+end('uses-feature')
body+=begin('application')+begin('activity',[('name',3,6)])+begin('intent-filter')+begin('action',[('name',3,9)])+end('action')
body+=begin('category',[('name',3,11)])+end('category')+end('intent-filter')+end('activity')
if web:
    body+=begin('activity',[('name',3,len(strings)-1)])+end('activity')
body+=end('application')+end('manifest')
manifest=struct.pack('<HHI',3,8,len(body)+8)+body
with zipfile.ZipFile(output/('WebStorage.apk' if web else 'KeyStore.apk' if keystore else 'Lifecycle.apk'),'w') as archive:
    archive.writestr('AndroidManifest.xml',manifest)
    archive.write(output/'classes.dex','classes.dex')
    if web:
        archive.write(Path(__file__).parent/'java/storage.html', 'assets/storage.html')
print('Built Java fixture:', output)
