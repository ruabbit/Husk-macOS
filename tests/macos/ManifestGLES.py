#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
import zipfile

def manifest(utf8=True, stripped=False):
    names=['uses-feature', '' if stripped else 'glEsVersion']
    blob=b''; offsets=[]
    for name in names:
        offsets.append(len(blob))
        blob += (bytes([len(name),len(name)])+name.encode()+b'\0' if utf8 else
                 struct.pack('<H',len(name))+name.encode('utf-16le')+b'\0\0')
    blob+=b'\0'*(-len(blob)%4)
    pool=struct.pack('<HHIIIIII',1,28,36+len(blob),2,0,0x100 if utf8 else 0,36,0)+struct.pack('<II',*offsets)+blob
    resource=struct.pack('<HHIII',0x180,8,16,0,0x01010281) if stripped else b''
    def feature(version):
        return (struct.pack('<HHIII',0x102,16,56,1,0xffffffff)+
                struct.pack('<IIHHHHHH',0xffffffff,0,20,20,1,0,0,0)+
                struct.pack('<IIIHBBI',0xffffffff,1,0xffffffff,8,0,0x11,version))
    body=pool+resource+feature(0x30002)+feature(0x20000)
    return struct.pack('<HHI',3,8,8+len(body))+body

with tempfile.TemporaryDirectory(prefix='husk-manifest-') as directory:
    cases=[]
    for utf8 in [True,False]:
        for stripped in [False,True]:
            data=manifest(utf8,stripped);cases.append((data,0x30002))
            # The container length alone may not legitimize a truncated element.
            short=bytearray(data[:-4]);struct.pack_into('<I',short,4,len(short));cases.append((short,0))
    data=manifest()
    for at,value in [(12,0),(12,0xffffffff),(36,0xffffffff)]:
        broken=bytearray(data);struct.pack_into('<I',broken,at,value);cases.append((broken,0))
    cases.extend([(b'',0),(data[:7],0)])
    command=[sys.argv[1]]
    for i,(data,want) in enumerate(cases):
        path=Path(directory)/f'{i}.apk'
        with zipfile.ZipFile(path,'w') as apk:apk.writestr('AndroidManifest.xml',data)
        command += [str(path),str(want)]
    subprocess.run(command,check=True)
