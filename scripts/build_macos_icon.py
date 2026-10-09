#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Package the upstream artwork as a macOS icon with standard and Retina sizes."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def build(source, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="husk-icon-", dir=output.parent) as folder:
        iconset = Path(folder) / "Husk.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                suffix = "@2x" if scale == 2 else ""
                destination = iconset / f"icon_{size}x{size}{suffix}.png"
                pixels = str(size * scale)
                subprocess.run(["sips", "--resampleHeightWidth", pixels, pixels,
                                str(source), "--out", str(destination)],
                               check=True, stdout=subprocess.DEVNULL)
        compiled = Path(folder) / "Husk.icns"
        subprocess.run(["iconutil", "--convert", "icns", "--output", str(compiled), str(iconset)], check=True)
        compiled.replace(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.source, args.output)
