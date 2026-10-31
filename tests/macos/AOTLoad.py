#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Execute controlled Android ELFs from signed dylibs with executable allocation disabled."""
import gzip
import io
import os
from pathlib import Path
import subprocess
import struct
import sys
import tarfile
import tempfile
import zipfile

tool, loader, namespace, fixture_root, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="AOT-", dir=output) as temporary:
    root = Path(temporary)
    cache = root / "cache with ' quote"
    cache.mkdir()
    def run(*args, env=None, code=0):
        result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=60)
        print(result.stdout, end="")
        print(result.stderr, end="")
        if result.returncode != code:
            raise RuntimeError(f"{args[0]}: exit {result.returncode}, expected {code}")
    env = dict(os.environ, TL_AOT_DIR=str(cache), TL_NO_XMEM="1", TL_NO_GUEST_JIT="1")
    for name in ("go-data", "mixed-data", "go-mixed-data", "mono-data"):
        source = fixture_root / (name + ".so")
        run(tool, "--prepare", cache, source)
        copy = root / ("lib_arm64-v8a_" + source.name)
        copy.write_bytes(source.read_bytes())
        stale = root / source.name
        changed = bytearray(copy.read_bytes())
        changed[-1] ^= 1
        stale.write_bytes(changed)
        check_env = dict(env, HUSK_REQUIRE_FILE_TRANSLATION="1") if name == "go-data" else env
        run(loader, source, copy, stale, env=check_env)
    # An unsupported unwind header is refused, without executing a constructor.
    malformed = bytearray((fixture_root / "mixed-data.so").read_bytes())
    phoff = struct.unpack_from("<Q", malformed, 32)[0]
    phsize, phcount = struct.unpack_from("<HH", malformed, 54)
    for i in range(phcount):
        pos = phoff + i * phsize
        if struct.unpack_from("<I", malformed, pos)[0] == 0x6474e550:
            offset = struct.unpack_from("<Q", malformed, pos + 8)[0]
            malformed[offset] = 2
            break
    else:
        raise RuntimeError("missing unwind header fixture")
    bad = root / "invalid-unwind.so"
    bad.write_bytes(malformed)
    run(tool, "--prepare", cache, bad)
    run(loader, bad, "reject-unwind", env=env)
    # Both namespaces need distinct hashed dylibs even with the same basename.
    run(tool, "--prepare", cache, fixture_root / "app.apk")
    run(tool, "--prepare-runtime", cache, fixture_root / "system/libcrypto.so", fixture_root / "system/libclient.so")
    for order in ("apk-first", "apk-system-first", "unpacked-first", "unpacked-system-first"):
        run(namespace, fixture_root, order, env=env)
    # Python-for-Android packages modules in a gzip tar named libpybundle.so.
    archive = io.BytesIO()
    with tarfile.open(fileobj=archive, mode="w") as tar:
        data = (fixture_root / "mixed-data.so").read_bytes()
        entry = tarfile.TarInfo("python/modules/nested/module.so")
        entry.size = len(data)
        tar.addfile(entry, io.BytesIO(data))
    apk = root / "python.apk"
    with zipfile.ZipFile(apk, "w") as package:
        package.writestr("lib/arm64-v8a/libpybundle.so", gzip.compress(archive.getvalue()))
    run(tool, "--prepare", cache, apk)
    module = root / "module.so"
    module.write_bytes(data)
    run(loader, module, env=env)
    # Missing AOT code is an ordinary load failure, never a JIT fallback.
    env["TL_AOT_DIR"] = str(root / "missing")
    run(loader, module, env=env, code=1)
print("PASS AOT relocations, code/data and syscall rewrites, namespaces, Python tar and no fallback")
