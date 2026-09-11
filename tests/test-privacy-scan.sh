#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
command -v node >/dev/null 2>&1 || { print -u2 'Node 22 or newer is required for scanner tests.'; exit 1; }
exec node --test "$ROOT/tests/test-publication-scan.mjs"
