#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  print 'Usage: scripts/package.sh --out NEW_ABSOLUTE_DIRECTORY [--media-review ABSOLUTE_PRIVATE_JSON]'
  exit 0
fi
command -v node >/dev/null 2>&1 || { print -u2 'Node 22 or newer is required for release engineering.'; exit 1; }
exec node "$ROOT/scripts/package.mjs" build --root "$ROOT" "$@"
