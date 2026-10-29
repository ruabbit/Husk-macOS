#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise upstream's experimental layout tool with a controlled Android ELF.

This verifies signed dyld loading, patched image bytes and RX/RW separation.
AOTLoad and packaged session tests cover relocation and dispatch separately;
controlled fixtures do not establish real-game compatibility.
"""
import pathlib
import subprocess
import sys
import tempfile


def main():
    tool, fixture, root = map(pathlib.Path, sys.argv[1:])
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ElfLayout-", dir=root) as directory:
        output = pathlib.Path(directory) / "fixture.dylib"
        subprocess.run([tool, fixture, output], check=True, timeout=20)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", output], check=True, timeout=20)
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", output], check=True, timeout=20)
        subprocess.run([tool, "--load", output, fixture], check=True, timeout=20)


if __name__ == "__main__":
    main()
