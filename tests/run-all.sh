#!/bin/zsh

set -eu

ROOT="${0:A:h:h}"
"$ROOT/scripts/verify-release.sh" "$ROOT"
"$ROOT/tests/test-privacy-scan.sh"
"$ROOT/tests/test-runtime.sh"
"$ROOT/tests/test-install.sh"
"$ROOT/tests/test-first-time-status.sh"
/bin/echo "All AutoAssist tests passed."
