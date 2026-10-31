#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""JNI preference durability across independent processes, in isolated data only."""
from pathlib import Path
import subprocess
import sys
import tempfile

binary, output = map(Path, sys.argv[1:])
with tempfile.TemporaryDirectory(prefix="JNIPrefs-", dir=output) as temporary:
    root = Path(temporary)
    def run(mode, folder=root):
        subprocess.run([binary, mode, folder], check=True, timeout=15)
    run("write")
    folder = root / "shared_prefs"
    saved = {p.name: p.read_bytes() for p in folder.iterdir()}
    assert len(saved) == 2 and all(p.stat().st_mode & 0o777 == 0o600 for p in folder.iterdir())
    run("empty", root / "other-game")
    # A path failure must not replace prior bytes or acknowledge close.
    folder.rename(root / "preserved")
    folder.write_text("blocked directory")
    run("failure")
    folder.unlink()
    (root / "preserved").rename(folder)
    assert saved == {p.name: p.read_bytes() for p in folder.iterdir()}
    run("read")
    # Malformed stores are not overwritten by defaults from an unreadable file.
    for corrupt in (b"invalid prefs\n", b"husk-prefs 1\nI\ti\tnot-a-number\n",
                    b"husk-prefs 1\nI\ti\t9999999999999999999\n",
                    b"husk-prefs 1\nZ\tz\tmaybe\n", b"husk-prefs 1\nS\ts\tbad\\x\n",
                    b"husk-prefs 1\nI\ti\t7\nI\ti\t8\n", b"husk-prefs 1\x00ignored\n"):
        for p in folder.iterdir():
            p.write_bytes(corrupt)
        run("failure")
        assert all(p.read_bytes() == corrupt for p in folder.iterdir())
print("PASS JNI preference cross-process reopen, game/name isolation, 0600 writes and failed/corrupt storage preservation")
