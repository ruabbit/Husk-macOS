#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Prepare a Java runtime from the pinned, offline Lineage image, never a guest disk."""
import argparse
import gzip
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import zipfile
import urllib.request

from build_java_framework import ROOT, LOCK, digest, source_digest, build as build_framework

RECORD = 'runtime-manifest.json'


def file_map(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise RuntimeError(f'Runtime may not contain symlinks: {path}')
        if path.is_file() and path.name != RECORD:
            result[path.relative_to(root).as_posix()] = {'sha256': digest(path), 'size': path.stat().st_size}
    return result


def verify(root, check_sources=False):
    lock = json.loads(LOCK.read_text())
    record = json.loads((root/RECORD).read_text())
    if record.get('imageSHA256') != lock['image']['sha256'] or record.get('lockSHA256') != digest(LOCK):
        raise RuntimeError('Java runtime source does not match dependency lock')
    if record.get('bootClassPath') != lock['bootClassPath'] or record.get('files') != file_map(root):
        raise RuntimeError('Java runtime resources are missing, stale or modified')
    required = {'framework-res.apk', 'husk-framework.json', 'Notices/system-NOTICE.xml.gz', 'system-build.prop'}
    required.update(lock['bootClassPath'])
    for module, spec in lock['modules'].items():
        required.add(f'Notices/{module}-NOTICE.html.gz')
        required.update(f'com.android.{module}/{f}' for f in spec['files'])
        for directory in spec['directories']:
            if not any((root/f'com.android.{module}'/directory).rglob('*')):
                raise RuntimeError(f'Missing Java runtime directory: {module}/{directory}')
    if not required <= record['files'].keys():
        raise RuntimeError('Java runtime manifest omits required files')
    for name in lock['bootClassPath']:
        path = root/name
        if name.endswith('.jar'):
            with zipfile.ZipFile(path) as archive:
                data = archive.read('classes.dex')
        else:
            data = path.read_bytes()
        if data[:4] != b'dex\n':
            raise RuntimeError(f'Boot class path is not DEX: {name}')
    framework = json.loads((root/'husk-framework.json').read_text())
    if framework['dexSHA256'] != digest(root/'husk-framework.dex') or framework['d8SHA256'] != lock['d8']['sha256']:
        raise RuntimeError('Framework provenance does not match DEX or D8')
    if check_sources and framework['sourcesSHA256'] != source_digest():
        raise RuntimeError('Framework DEX is stale relative to the checked-in sources')
    for path in root.rglob('*.so'):
        header = path.read_bytes()[:64]
        if header[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', header, 18)[0] != 183:
            raise RuntimeError(f'Expected Android arm64 ELF resource: {path}')
    return record


def write_record(root):
    lock = json.loads(LOCK.read_text())
    record = {'schema': 1, 'imageSHA256': lock['image']['sha256'], 'lockSHA256': digest(LOCK),
              'bootClassPath': lock['bootClassPath'], 'files': file_map(root)}
    (root/RECORD).write_text(json.dumps(record, indent=2)+'\n')
    verify(root, check_sources=True)


def system_partition(raw, destination):
    # Read GPT and Android logical-partition metadata, without mounting or root privileges.
    with raw.open('rb') as source:
        source.seek(512); header = source.read(512)
        if header[:8] != b'EFI PART':
            raise RuntimeError('Pinned image has no GPT')
        lba, count, size = struct.unpack_from('<QII', header, 72)
        if count > 256 or size < 128 or size > 4096:
            raise RuntimeError('Invalid partition table')
        source.seek(lba*512); table = source.read(count*size)
        base = None
        for i in range(count):
            entry = table[i*size:(i+1)*size]
            if entry[56:128].decode('utf-16le').rstrip('\0') == 'super':
                base = struct.unpack_from('<Q', entry, 32)[0]*512
        if base is None:
            raise RuntimeError('Pinned image has no super partition')
        source.seek(base+12288); header = source.read(256)
        magic, _, _, hsize = struct.unpack_from('<IHHI', header)
        tsize = struct.unpack_from('<I', header, 44)[0]
        if magic != 0x414c5030 or hsize > 4096 or tsize > 1 << 20:
            raise RuntimeError('Invalid logical-partition metadata')
        po, pn, ps = struct.unpack_from('<III', header, 80)
        eo, en, es = struct.unpack_from('<III', header, 92)
        source.seek(base+12288+hsize); table = source.read(tsize)
        if ps < 52 or es < 24 or po+pn*ps > tsize or eo+en*es > tsize:
            raise RuntimeError('Invalid logical-partition extents')
        for i in range(pn):
            entry = table[po+ps*i:po+ps*(i+1)]
            if entry[:36].split(b'\0')[0] != b'system':
                continue
            _, first, number, _ = struct.unpack_from('<IIII', entry, 36)
            if first+number > en:
                raise RuntimeError('System extents outside table')
            with destination.open('wb') as output:
                for j in range(first, first+number):
                    sectors, kind, offset, device = struct.unpack_from('<QIQI', table, eo+es*j)
                    if kind != 0 or device != 0:
                        raise RuntimeError('Unexpected system extent type')
                    source.seek(base+offset*512)
                    left = sectors*512
                    while left:
                        block = source.read(min(left, 16 << 20))
                        if not block:
                            raise RuntimeError('Truncated system partition')
                        output.write(block); left -= len(block)
            return
    raise RuntimeError('No system logical partition')


def extract(work, output, debugfs):
    lock = json.loads(LOCK.read_text())
    output.mkdir(parents=True, exist_ok=True)
    (output/'Notices').mkdir(exist_ok=True)

    def dump(image, source, dest, directory=False):
        dest.parent.mkdir(parents=True, exist_ok=True)
        # debugfs is read-only unless -w is used. Its command language needs quoted paths.
        if any(c in str(dest) for c in ['"', '\\', '\n']):
            raise RuntimeError('Unsupported extraction output path')
        command = f'rdump {source} "{dest.parent}"' if directory else f'dump {source} "{dest}"'
        result = subprocess.run([debugfs, '-R', command, image], capture_output=True, text=True, check=True)
        if not dest.exists():
            raise RuntimeError(f'Could not extract {source}: {result.stderr.strip()}')

    for name, spec in lock['modules'].items():
        archive = work/spec['archive']
        dump(work/'system.img', f'/system/apex/{spec["archive"]}', archive)
        with zipfile.ZipFile(archive) as outer:
            inner = zipfile.ZipFile(io.BytesIO(outer.read('original_apex'))) if 'original_apex' in outer.namelist() else outer
            payload = work/f'{name}.img'
            with inner.open('apex_payload.img') as src, payload.open('wb') as dst:
                shutil.copyfileobj(src, dst)
            notice = inner.read('assets/NOTICE.html.gz')
            gzip.decompress(notice)  # reject missing or corrupt notices
            (output/'Notices'/f'{name}-NOTICE.html.gz').write_bytes(notice)
            if inner is not outer:
                inner.close()
        for path in spec['files']:
            dump(payload, '/'+path, output/f'com.android.{name}'/path)
        for path in spec['directories']:
            dump(payload, '/'+path, output/f'com.android.{name}'/path, directory=True)
        payload.unlink(); archive.unlink()
    # Keep all framework densities on macOS, where window sizes/scales vary.
    for source, dest in [('framework/framework-res.apk', 'framework-res.apk'),
                         ('framework/org.apache.http.legacy.jar', 'org.apache.http.legacy.jar'),
                         ('etc/NOTICE.xml.gz', 'Notices/system-NOTICE.xml.gz'),
                         ('build.prop', 'system-build.prop')]:
        dump(work/'system.img', '/system/'+source, output/dest)


def prepare(image, output):
    lock = json.loads(LOCK.read_text())
    if image.is_symlink() or image.stat().st_size != lock['image']['size'] or digest(image) != lock['image']['sha256']:
        raise RuntimeError('Expected the immutable vda-v12 download from java-runtime.lock.json, not an installed guest disk')
    info = json.loads(subprocess.check_output(['qemu-img', 'info', '--output=json', image], text=True))
    if info.get('backing-filename') or info.get('format') != 'qcow2':
        raise RuntimeError('Expected a standalone qcow2 source image')
    debugfs = shutil.which('debugfs')
    if not debugfs:
        debugfs = next((str(p) for p in [Path('/opt/homebrew/opt/e2fsprogs/sbin/debugfs'), Path('/usr/local/opt/e2fsprogs/sbin/debugfs')] if p.is_file()), None)
    if not debugfs:
        raise RuntimeError('Install e2fsprogs or put debugfs on PATH')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='java-extract-', dir=output.parent) as temporary:
        work = Path(temporary)
        subprocess.run(['qemu-img', 'convert', '-f', 'qcow2', '-O', 'raw', image, work/'source.raw'], check=True)
        system_partition(work/'source.raw', work/'system.img')
        (work/'source.raw').unlink()
        extract(work, work/'runtime', debugfs)
        build_framework(work/'runtime/husk-framework.dex')
        write_record(work/'runtime')
        if output.exists():
            shutil.rmtree(output)
        shutil.move(work/'runtime', output)


def ensure(output):
    if (output/RECORD).exists():
        verify(output)
        record = json.loads((output/'husk-framework.json').read_text())
        if record['sourcesSHA256'] != source_digest():
            build_framework(output/'husk-framework.dex')
            write_record(output)
        return
    # Reuse the immutable original download; never inspect an installed VM disk.
    explicit = os.environ.get('HUSK_JAVA_IMAGE')
    previous = ROOT/'build/macos-p5/guest-cache/vda-v12.qcow2'
    image = Path(explicit).expanduser() if explicit else previous
    if explicit or image.is_file():
        prepare(image, output)
        return
    lock = json.loads(LOCK.read_text())
    cache = output.parent/'Cache'
    cache.mkdir(parents=True, exist_ok=True)
    image = cache/'vda-v12.qcow2'
    if not image.exists():
        partial = image.with_suffix('.qcow2.partial')
        try:
            print('Downloading pinned Java source image (about 2 GB)', flush=True)
            with urllib.request.urlopen(lock['image']['url'], timeout=60) as source, partial.open('wb') as target:
                shutil.copyfileobj(source, target, 1 << 20)
            if partial.stat().st_size != lock['image']['size'] or digest(partial) != lock['image']['sha256']:
                raise RuntimeError('Downloaded Java source image failed its size/hash check')
            partial.replace(image)
        finally:
            partial.unlink(missing_ok=True)
    prepare(image, output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'build/macos/JavaRuntime')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--image', type=Path, help='Pinned, unused original download; opened read-only')
    group.add_argument('--refresh-framework', action='store_true')
    group.add_argument('--verify', action='store_true')
    group.add_argument('--ensure', action='store_true', help='Verify/reuse resources or prepare from the pinned source download')
    args = parser.parse_args()
    if args.image:
        prepare(args.image.absolute(), args.output.resolve())
    elif args.ensure:
        ensure(args.output.resolve())
    elif args.refresh_framework:
        # Verify old resource hashes before replacing only our framework and its provenance.
        verify(args.output)
        build_framework(args.output/'husk-framework.dex')
        write_record(args.output)
    else:
        verify(args.output, check_sources=True)
    print(f'PASS Java runtime: {args.output}')
