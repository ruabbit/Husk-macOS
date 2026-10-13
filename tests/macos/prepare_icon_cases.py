#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Small compiled Android resources with known pixels; no game artwork."""
import struct
import sys
import zlib
import zipfile
from pathlib import Path

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
u32 = lambda n: struct.pack('<I', n)

def pool(strings):
    offsets, data = [], b''
    for s in strings:
        offsets.append(len(data)); b = s.encode()
        data += bytes([len(s), len(b)]) + b + b'\0'
    data += bytes(-len(data) % 4)
    start = 28 + 4 * len(strings)
    return struct.pack('<HHIIIIII', 1, 28, start + len(data), len(strings), 0, 0x100, start, 0) + b''.join(map(u32, offsets)) + data

def xml(elements, ids=None):
    strings = list(dict.fromkeys([s for name, attrs in elements for s in [name, *attrs]]))
    index = strings.index
    body = pool(strings)
    if ids:
        body += struct.pack('<HHI', 0x180, 8, 8 + 4*len(strings)) + b''.join(u32(ids.get(s, 0)) for s in strings)
    for name, attrs in elements:
        values = b''.join(struct.pack('<IIIHBBI', 0xffffffff, index(k), 0xffffffff, 8, 0, kind, v) for k, (kind, v) in attrs.items())
        body += struct.pack('<HHIII', 0x102, 16, 36 + len(values), 1, 0xffffffff)
        body += struct.pack('<IIHHHHHH', 0xffffffff, index(name), 20, 20, len(attrs), 0, 0, 0) + values
    return struct.pack('<HHI', 3, 8, 8+len(body)) + body

def table(entries):
    strings = [v for _, (kind, v) in entries.items() if kind == 3]
    if not strings: strings = ['unused']
    count = max(entries)+1
    values, offsets = b'', []
    for i in range(count):
        if i not in entries: offsets.append(0xffffffff); continue
        offsets.append(len(values)); kind, v = entries[i]
        values += struct.pack('<HHIHBBI', 8, 0, i, 8, 0, kind, strings.index(v) if kind == 3 else v)
    header = 52; start = header+4*count
    config = bytearray(32); struct.pack_into('<I', config, 0, 32); struct.pack_into('<H', config, 14, 480)
    chunk = struct.pack('<HHIBBHII', 0x201, header, start+len(values), 1, 0, 0, count, start) + config
    chunk += b''.join(map(u32, offsets)) + values
    package = struct.pack('<HHII', 0x200, 12, 12+len(chunk), 0x7f) + chunk
    body = pool(strings) + package
    return struct.pack('<HHII', 2, 12, 12+len(body), 1) + body

def png(pixel):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind+data))
    pixels = b''.join(b'\0' + b''.join(bytes(pixel(x,y)) for x in range(108)) for y in range(108))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',108,108,8,6,0,0,0)) + chunk(b'IDAT',zlib.compress(pixels)) + chunk(b'IEND',b'')

manifest = xml([('manifest', {}), ('application', {'icon': (1,0x7f010000)})], {'icon':0x01010002})
adaptive = xml([('adaptive-icon', {}), ('background', {'drawable': (1,0x7f010002)}), ('foreground', {'drawable': (1,0x7f010001)})])
fore = png(lambda x,y: (255,0,0,255) if 36<=x<72 and 36<=y<72 else (0,0,0,0))
back = png(lambda x,y: (0,0,255,255) if y<54 else (0,255,0,255))
def apk(name, files):
    with zipfile.ZipFile(out/name, 'w') as z:
        for path, data in files.items(): z.writestr(path, data)

apk('base.apk', {'AndroidManifest.xml':manifest, 'resources.arsc':table({0:(3,'res/icon.xml')}), 'res/icon.xml':adaptive})
apk('layers.apk', {'resources.arsc':table({1:(3,'res/fore.png'),2:(3,'res/back.png')}), 'res/fore.png':fore, 'res/back.png':back})
apk('density.apk', {'resources.arsc':table({0:(3,'res/bitmap.png')}), 'res/bitmap.png':back})
apk('color.apk', {'resources.arsc':table({1:(3,'res/fore.png'),2:(0x1c,0xff0000ff)}), 'res/fore.png':fore})
apk('bitmap.apk', {'AndroidManifest.xml':manifest, 'resources.arsc':table({0:(3,'res/bitmap.png')}), 'res/bitmap.png':back})
apk('manifest-only.apk', {'AndroidManifest.xml':manifest})
(out/'ready').write_text('Synthetic split bitmap and adaptive icon cases\n')
