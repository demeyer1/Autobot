#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
command -v node >/dev/null 2>&1 || { print -u2 'Node 22 or newer is required for the engineering tests.'; exit 1; }
"$ROOT/tests/test-privacy-scan.sh"
"$ROOT/tests/test-runtime.sh"
"$ROOT/tests/test-install.sh"
"$ROOT/tests/test-install-security.sh"
"$ROOT/tests/test-install-upgrade.sh"
"$ROOT/tests/test-install-interruption.sh"
"$ROOT/tests/test-first-time-status.sh"
"$ROOT/tests/test-first-time-walkthrough.sh"
print 'All focused AutoAssist engineering tests passed. Release media review and actual packaged/downloaded acceptance are separate gates.'
