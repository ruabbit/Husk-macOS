#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
HUSK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HUSK_BUILD="${HUSK_BUILD_DIR:-$HUSK_ROOT/build/macos}"
"$HUSK_ROOT/scripts/build_macos.sh"
python3 "$HUSK_ROOT/scripts/verify_macos_bundle.py" "$HUSK_BUILD/Product/HuskMac.app" --output "$HUSK_BUILD/bundle-verification.json"
ctest --test-dir "$HUSK_BUILD" --output-on-failure
