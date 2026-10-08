#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build deterministic, repository-owned arm64 ELF game packages, never download games."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import zlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def tool(variable, candidates):
    for name in [os.environ.get(variable), *candidates]:
        if name and (path := shutil.which(str(name))):
            return path
    raise RuntimeError(f"Install LLVM / Android NDK or set {variable}; no toolchain is downloaded automatically")

def icon(variant):
    def chunk(name, body):
        return struct.pack('>I', len(body)) + name + body + struct.pack('>I', zlib.crc32(name + body))
    raw = bytearray()
    for y in range(128):
        raw.append(0)
        for x in range(128):
            d = (x-64)**2 + (y-64)**2
            color = (20, 30, 48, 255)
            if 35**2 < d < 42**2: color = (85, 200, 225, 255) if not variant else (166, 140, 245, 255)
            if abs(x-90) < 10 and abs(y-30) < 10: color = (242, 175, 52, 255)
            if abs(x-60) < 11 and abs(y-73) < 11: color = (225, 244, 245, 255)
            raw.extend(color)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',128,128,8,6,0,0,0)) + chunk(b'IDAT',zlib.compress(raw)) + chunk(b'IEND',b'')

def build(output):
    output.mkdir(parents=True, exist_ok=True)
    ndk = sorted((Path.home() / "Library/Android/sdk/ndk").glob("*/toolchains/llvm/prebuilt/darwin-*/bin"), reverse=True)
    cc = tool("ELF_CC", ["/opt/homebrew/opt/llvm/bin/clang", *[p/'clang' for p in ndk]])
    ld = tool("ELF_LD", ["ld.lld", *[p/'ld.lld' for p in ndk], "/opt/homebrew/opt/llvm/bin/ld.lld"])
    source = ROOT / "tests/macos/fixture/orbit.c"
    subprocess.run([cc,"--target=aarch64-linux-android29","-O2","-fPIC","-ffreestanding","-fno-stack-protector",
                    "-mno-outline-atomics","-c",str(source),"-o",str(output/'orbit.o')],check=True)
    lib = output / "libhusk_orbit.so"
    subprocess.run([ld,"-shared","--no-relax","--hash-style=gnu","-soname",lib.name,"-z","max-page-size=16384",
                    str(output/'orbit.o'),"-o",str(lib)],check=True)
    for variant, title in [(0,"Orbit Garden"),(1,"Orbit Garden · Dusk")]:
        manifest = dict(schema=1,id=f"org.husk.orbit.{variant}", title=title, abi=1,library=lib.name,variant=variant,icon="assets/icon.png")
        entries = {"AndroidManifest.xml":f'<manifest package="org.husk.orbit.{variant}"/>'.encode(),
                   "assets/husk-fixture.json":json.dumps(manifest,sort_keys=True).encode(),"assets/icon.png":icon(variant),
                   f"lib/arm64-v8a/{lib.name}":lib.read_bytes()}
        with zipfile.ZipFile(output/f"OrbitGarden{'Dusk' if variant else ''}.apk","w") as archive:
            for name,data in sorted(entries.items()):
                item=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0));item.compress_type=zipfile.ZIP_DEFLATED
                item.external_attr=0o100644 << 16;archive.writestr(item,data)
    catalog = {"schema":1,"abi":1,"sha256":hashlib.sha256(lib.read_bytes()).hexdigest()}
    (output/"fixture-catalog.json").write_text(json.dumps(catalog,indent=2)+"\n")
    (output/"provenance.json").write_text(json.dumps({"cc":subprocess.check_output([cc,"--version"],text=True),
        "ld":subprocess.check_output([ld,"--version"],text=True),"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),**catalog},indent=2)+"\n")

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True)
    build(parser.parse_args().output)
