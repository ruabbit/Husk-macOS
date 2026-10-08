#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
HUSK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HUSK_BUILD="${HUSK_BUILD_DIR:-$HUSK_ROOT/build/macos}"
HUSK_DEPS="${HUSK_DEPS_DIR:-$HUSK_ROOT/build/macos-deps}"
if [ ! -f "$HUSK_DEPS/lib/libANGLE-shared.dylib" ] || [ ! -d "$HUSK_DEPS/lib/MoltenVK.framework" ]; then
    python3 "$HUSK_ROOT/scripts/build_macos_graphics.py"
fi
cmp "$HUSK_ROOT/dependencies/macos.lock.json" "$HUSK_DEPS/lock.json"
python3 "$HUSK_ROOT/scripts/build_macos_graphics.py" --verify "$HUSK_DEPS"
cmake -S "$HUSK_ROOT" -B "$HUSK_BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" -DHUSK_DEPS="$HUSK_DEPS" "$@"
cmake --build "$HUSK_BUILD" --parallel "${HUSK_BUILD_JOBS:-4}"
