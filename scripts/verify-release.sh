#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  print 'Usage: scripts/verify-release.sh [ABSOLUTE_SOURCE_ROOT] [--media-review ABSOLUTE_PRIVATE_JSON]'
  print 'For an archive use node scripts/package.mjs verify --help (see package.mjs --help).'
  exit 0
fi
if [[ $# -gt 0 && "$1" != --* ]]; then ROOT="$1"; shift; fi
command -v node >/dev/null 2>&1 || { print -u2 'Node 22 or newer is required for release verification.'; exit 1; }
exec node "${0:A:h}/package.mjs" check --root "$ROOT" "$@"
