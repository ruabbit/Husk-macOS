#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
import json
from pathlib import Path
import sys
import zipfile

fixture, out = map(Path, sys.argv[1:])
out.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(out / 'compressed.xapk', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    archive.write(fixture / 'OrbitGarden.apk', 'base.apk')
with zipfile.ZipFile(out / 'duplicate.apks', 'w') as archive:
    archive.write(fixture / 'OrbitGarden.apk', '../base.apk')
    archive.write(fixture / 'OrbitGarden.apk', 'other/base.apk')
with zipfile.ZipFile(out / 'unsupported.apk', 'w') as archive:
    archive.writestr('AndroidManifest.xml', '<manifest package="test.unsupported"/>')
    archive.writestr('classes.dex', b'not-an-engine')
with zipfile.ZipFile(out / 'forged.apk', 'w') as archive:
    archive.writestr('AndroidManifest.xml', '<manifest/>')
    archive.writestr('assets/husk-fixture.json', json.dumps(dict(schema=1,id='org.husk.orbit.0',title='Forged',abi=1,library='libhusk_orbit.so',variant=0,icon='')))
    archive.writestr('lib/arm64-v8a/libhusk_orbit.so', b'not an ELF')
(out / 'damaged.apk').write_bytes((fixture / 'OrbitGarden.apk').read_bytes()[:70])
(out / 'ready').write_text('synthetic cases only\n')
