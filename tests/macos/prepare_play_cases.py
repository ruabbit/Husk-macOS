#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Synthetic APK sets, independently signed with OpenSSL; no user APKs or keys."""
import hashlib
import io
from pathlib import Path
import struct
import subprocess
import sys
import zipfile
from zip64_fixture import force_zip64

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
le = lambda n: struct.pack('<I', n)
lp = lambda data: le(len(data)) + data

def manifest(package, version, split=None):
    strings = ['manifest', 'package', 'versionCode', package]
    if split:
        strings += ['split', split]
    encoded = b''
    offsets = []
    for s in strings:
        offsets.append(len(encoded))
        b = s.encode()
        encoded += bytes([len(s), len(b)]) + b + b'\0'
    encoded += b'\0' * (-len(encoded) % 4)
    start = 28 + 4 * len(strings)
    pool = struct.pack('<HHIIIIII', 1, 28, start + len(encoded), len(strings), 0, 0x100, start, 0) + b''.join(le(x) for x in offsets) + encoded
    def attr(name, kind, value):
        return struct.pack('<IIIHBBI', 0xffffffff, name, value if kind == 3 else 0xffffffff, 8, 0, kind, value)
    attrs = attr(1, 3, 3) + attr(2, 0x10, version)
    if split:
        attrs += attr(4, 3, 5)
    element = struct.pack('<HHIII', 0x102, 16, 36 + len(attrs), 1, 0xffffffff)
    element += struct.pack('<IIHHHHHH', 0xffffffff, 0, 20, 20, len(attrs)//20, 0, 0, 0) + attrs
    return struct.pack('<HHI', 3, 8, 8 + len(pool) + len(element)) + pool + element

def run(args, data=None):
    return subprocess.run(args, input=data, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

keys = []
for name in ('same', 'other'):
    key = out / (name + '.key')
    cert = out / (name + '.pem')
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key), '-out', str(cert), '-subj', '/CN=Husk synthetic APK test/', '-days', '1'])
    der = run(['openssl', 'x509', '-in', str(cert), '-outform', 'DER'])
    public = run(['openssl', 'pkey', '-in', str(key), '-pubout', '-outform', 'DER'])
    keys.append((key, der, public))

def apk(name, version=1, split=None, package='org.husk.playtest', key=0, v3=False):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', compression=zipfile.ZIP_STORED) as z:
        z.writestr('AndroidManifest.xml', manifest(package, version, split))
        z.writestr('assets/test.txt', (name + '-payload').encode())
    data = buf.getvalue()
    end = len(data) - 22
    cd = struct.unpack_from('<I', data, end + 16)[0]
    digests = []
    for section in (data[:cd], data[cd:end], data[end:]):
        for i in range(0, len(section), 1 << 20):
            b = section[i:i+(1 << 20)]
            digests.append(hashlib.sha256(b'\xa5' + le(len(b)) + b).digest())
    digest = hashlib.sha256(b'\x5a' + le(len(digests)) + b''.join(digests)).digest()
    private, cert, public = keys[key]
    sdk = le(28) + le(0x7fffffff) if v3 else b''
    signed = lp(lp(le(0x0103) + lp(digest))) + lp(lp(cert)) + sdk + lp(b'')
    signature = run(['openssl', 'dgst', '-sha256', '-sign', str(private)], signed)
    signer = lp(signed) + sdk + lp(lp(le(0x0103) + lp(signature))) + lp(public)
    value = lp(lp(signer))
    pair = struct.pack('<Q', 4 + len(value)) + le(0xf05368c0 if v3 else 0x7109871a) + value
    size = len(pair) + 24
    block = struct.pack('<Q', size) + pair + struct.pack('<Q', size) + b'APK Sig Block 42'
    eocd = bytearray(data[end:]); struct.pack_into('<I', eocd, 16, cd + len(block))
    (out/name).write_bytes(data[:cd] + block + data[cd:end] + eocd)

for version in (1, 2):
    apk(f'base-v{version}.apk', version, v3=version == 2)
    for i in range(47 if version == 1 else 6):
        apk(f'split{i}-v{version}.apk', version, f'config.test{i}', v3=version == 2)
apk('wrong-key.apk', 2, key=1)
apk('wrong-package.apk', 1, 'config.wrong', package='org.husk.different')
apk('wrong-split-key.apk', 1, 'config.wrong', key=1)
for bad in [False, True]:
    with zipfile.ZipFile(out/('foreign-obb.xapk' if bad else 'expanded.xapk'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(out/'base-v1.apk', 'base.apk')
        package = 'org.other.game' if bad else 'org.husk.playtest'
        z.writestr(f'Android/obb/{package}/main.1.{package}.obb', b'archived main resource')
with zipfile.ZipFile(out/'arbitrary.apks', 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(out/'base-v1.apk', 'config.arm64_v8a.apk')
    for i, name in enumerate(['base.apk', 'models.apk', 'textures.apk', 'z.apk', 'a.apk', 'stuff.apk']):
        z.write(out/f'split{i}-v1.apk', name)
(out/'expanded-zip64.xapk').write_bytes(force_zip64((out/'expanded.xapk').read_bytes()))
b = bytearray((out/'base-v1.apk').read_bytes()); b[50] ^= 1; (out/'tampered.apk').write_bytes(b)
# Network-provided ZIP metadata and signing-block sizes must fail without traps.
for n, b in [('short', b'PK'), ('overflow', b'\xff' * 80)]:
    (out/f'{n}.apk').write_bytes(b)
for key, _, _ in keys:
    key.unlink(); key.with_suffix('.pem').unlink()
(out/'ready').write_text('Synthetic signed Play sets\n')
