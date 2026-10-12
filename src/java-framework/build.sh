#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/../../scripts/build_java_framework.py" "${1:-$HERE/../../build/husk-framework.dex}"
