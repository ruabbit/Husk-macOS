#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
HUSK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HUSK_BUILD="${HUSK_BUILD_DIR:-$HUSK_ROOT/build/macos}"
export HUSK_TEST_FAILURE_LATCH="${HUSK_TEST_FAILURE_LATCH:-$HUSK_ROOT/build/logs/current-macos-runner-fault.json}"
mkdir -p "$(dirname "$HUSK_TEST_FAILURE_LATCH")"
if [ -e "$HUSK_TEST_FAILURE_LATCH" ]; then
    echo "Runner validation stopped; inspect $HUSK_TEST_FAILURE_LATCH before resuming." >&2
    exit 1
fi
"$HUSK_ROOT/scripts/build_macos.sh"
python3 "$HUSK_ROOT/scripts/verify_macos_bundle.py" "$HUSK_BUILD/Product/HuskMac.app" --output "$HUSK_BUILD/bundle-verification.json"
ctest --test-dir "$HUSK_BUILD" --output-on-failure --stop-on-failure
