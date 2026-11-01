# SPDX-License-Identifier: GPL-2.0-or-later
from pathlib import Path
import struct,sys
def classes(path):
    data=Path(path).read_bytes()
    u32=lambda offset:struct.unpack_from('<I',data,offset)[0]
    strings=[]
    for i in range(u32(56)):
        pos=u32(u32(60)+i*4)
        while data[pos]&128:pos+=1
        pos+=1
        strings.append(data[pos:data.index(0,pos)].decode())
    types=[strings[u32(u32(68)+i*4)] for i in range(u32(64))]
    return {types[u32(u32(100)+i*32)] for i in range(u32(96))}
root=Path(sys.argv[1]);full=classes(root/'husk-framework.dex');core=classes(root/'husk-framework-core.dex')
assert core<full
assert 'Lhusk/AppRunner;' in core and 'Landroid/app/Activity;' in core
assert 'Landroid/location/LocationManager;' in full-core
assert all(x in core for x in full if x.startswith('Landroid/app/Activity$'))
print(f'PASS core DEX retains handwritten and nested classes: {len(core)} of {len(full)} classes')
