#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Fetch verified cold-boot assets and prepare a new private VM directory."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import zipfile
from build_macos_vm import ROOT, LOCK, download, digest

def prepare(destination, cache):
    guest = LOCK['guest']
    cache.mkdir(parents=True, exist_ok=True)
    base = cache/'vda-v12.qcow2'
    download(guest['url'], base, guest['sha256'])
    archive = cache/'Husk-0.9.0.ipa'
    download(guest['seedArchive']['url'], archive, guest['seedArchive']['sha256'])
    with zipfile.ZipFile(archive) as z:
        for name, expected in guest['seeds'].items():
            p = cache/name
            if not p.exists():
                members = [s for s in z.namelist() if Path(s).name == name]
                if len(members) != 1: raise RuntimeError(f'Ambiguous seed {name}')
                p.write_bytes(z.read(members[0]))
            if digest(p) != expected: raise RuntimeError(f'Seed hash mismatch: {name}')
    if destination.exists():
        raise RuntimeError('Destination already exists; refusing to replace VM disks')
    destination.mkdir(parents=True)
    try:
        # APFS clone if available, ordinary independent copy elsewhere. No backing
        # image path can disappear under an installed guest.
        for source, name in [(base, 'system.qcow2'), (cache/'lineage-vdb-seed.qcow2', 'userdata.qcow2'),
                             (cache/'lineage-efi-vars-seed.fd', 'vars.qcow2'), (cache/'edk2-aarch64-code.fd', 'firmware.fd')]:
            result = subprocess.run(['/bin/cp', '-c', source, destination/name], capture_output=True)
            if result.returncode: shutil.copy2(source, destination/name)
        manifest = {'schema': 1, 'generation': guest['generation'], 'systemSourceSHA256': guest['sha256'],
                    'firmwareSHA256': guest['seeds']['edk2-aarch64-code.fd'], 'seedSHA256': guest['seeds'],
                    'coldBootOnly': True}
        (destination/'guest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    except Exception:
        # Preserve partial work for diagnosis; it must not pass as ready.
        (destination/'INCOMPLETE').touch()
        raise
    print(destination)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--destination', type=Path, required=True)
    p.add_argument('--cache', type=Path, default=ROOT/'build/macos-p5/guest-cache')
    a = p.parse_args()
    prepare(a.destination.resolve(), a.cache.resolve())
