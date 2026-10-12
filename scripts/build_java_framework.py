#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build the checked-in framework without changing generated source files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'dependencies/java-runtime.lock.json'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def sources():
    base = ROOT / 'src/java-framework'
    return sorted([*base.rglob('*.java'), *base.glob('gen/*.py'),
                   ROOT / 'scripts/build_java_framework.py', LOCK])


def source_digest():
    h = hashlib.sha256()
    for path in sources():
        h.update(path.relative_to(ROOT).as_posix().encode() + b'\0' + path.read_bytes() + b'\0')
    return h.hexdigest()


def toolchain():
    lock = json.loads(LOCK.read_text())
    candidates = [os.environ.get('HUSK_JDK'), os.environ.get('JAVA_HOME')]
    located = subprocess.run(['/usr/libexec/java_home', '-v', str(lock['jdkMajor'])], capture_output=True, text=True)
    if located.returncode == 0:
        candidates.append(located.stdout.strip())
    candidates += [f'/opt/homebrew/opt/openjdk@{lock["jdkMajor"]}/libexec/openjdk.jdk/Contents/Home',
                   f'/usr/local/opt/openjdk@{lock["jdkMajor"]}/libexec/openjdk.jdk/Contents/Home']
    jdk = next((Path(p) for p in candidates if p and (Path(p)/'bin/javac').is_file()), None)
    if not jdk:
        raise RuntimeError('JDK 21 required: set HUSK_JDK to its Contents/Home')
    version = subprocess.check_output([jdk/'bin/javac', '-version'], text=True).strip()
    if not version.startswith(f'javac {lock["jdkMajor"]}.'):
        raise RuntimeError(f'Expected JDK {lock["jdkMajor"]}, got {version}')
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT', os.environ.get('ANDROID_HOME', str(Path.home()/'Library/Android/sdk'))))
    d8 = Path(os.environ.get('HUSK_D8', str(sdk/'build-tools'/lock['d8']['sdkBuildTools']/'lib/d8.jar')))
    if not d8.is_file() or digest(d8) != lock['d8']['sha256']:
        raise RuntimeError('D8 does not match java-runtime.lock.json; install SDK build-tools 36.0.0 or set HUSK_D8')
    return jdk, d8, version


def jar_classes(directory, destination):
    # Fixed member order and times keep the DEX input independent of checkout times.
    with zipfile.ZipFile(destination, 'w') as jar:
        for path in sorted(directory.rglob('*.class')):
            jar.writestr(zipfile.ZipInfo(path.relative_to(directory).as_posix(), (2000, 1, 1, 0, 0, 0)), path.read_bytes())


def build(output):
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    jdk, d8, version = toolchain()
    base = ROOT/'src/java-framework'
    with tempfile.TemporaryDirectory(prefix='framework-', dir=output.parent) as temporary:
        work = Path(temporary)
        subprocess.run(['python3', base/'gen/gles20.py', work/'generated', work/'gles20.c'], check=True, stdout=subprocess.DEVNULL)
        if (work/'gles20.c').read_bytes() != (ROOT/'src/translation-layer-next/husk-tl-dvm-gles20.c').read_bytes():
            raise RuntimeError('GLES20 generated C is stale; regenerate it explicitly before building')
        if (work/'generated/GLES20.java').read_bytes() != (base/'src/android/opengl/GLES20.java').read_bytes():
            raise RuntimeError('GLES20 generated Java is stale; regenerate it explicitly before building')
        for kind, paths in [('stubs', sorted((base/'stubs').rglob('*.java'))),
                            ('classes', sorted([*(base/'src').rglob('*.java'), *(base/'gen-src').rglob('*.java')]))]:
            arguments = work/f'{kind}.args'
            arguments.write_text('\n'.join('"'+str(p).replace('\\', '\\\\').replace('"', '\\"')+'"' for p in paths)+'\n')
            subprocess.run([jdk/'bin/javac', '-nowarn', '--release', '8', '-encoding', 'UTF-8',
                            '-cp', work/'stubs', '-d', work/kind, '@'+str(arguments)], check=True)
            jar_classes(work/kind, work/f'{kind}.jar')
        subprocess.run([jdk/'bin/java', '-cp', d8, 'com.android.tools.r8.D8', '--min-api', '26',
                        '--lib', jdk, '--classpath', work/'stubs.jar', '--output', work, work/'classes.jar'], check=True)
        if (work/'classes2.dex').exists():
            raise RuntimeError('Framework unexpectedly exceeds one DEX; update boot class path before packaging')
        shutil.copyfile(work/'classes.dex', output)
    record = {'schema': 1, 'sourcesSHA256': source_digest(), 'dexSHA256': digest(output),
              'compiler': version, 'd8SHA256': digest(d8), 'minAPI': 26, 'javaRelease': 8}
    output.with_suffix('.json').write_text(json.dumps(record, indent=2)+'\n')
    print(f'Built {output} ({output.stat().st_size} bytes)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    build(parser.parse_args().output)
