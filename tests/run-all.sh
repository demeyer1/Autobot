#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
command -v node >/dev/null 2>&1 || { print -u2 'Node 22 or newer is required for the engineering tests.'; exit 1; }
/bin/zsh "$ROOT/tests/test-privacy-scan.sh"
node --test "$ROOT/tests/test-publication-scan.mjs"
node "$ROOT/tests/test-core.mjs"
/bin/zsh "$ROOT/tests/test-actual-node-absent.sh"
/bin/zsh "$ROOT/tests/test-runtime.sh"
/bin/zsh "$ROOT/tests/test-supported-node-install.sh"
/bin/zsh "$ROOT/tests/test-install.sh"
/bin/zsh "$ROOT/tests/test-install-security.sh"
/bin/zsh "$ROOT/tests/test-install-upgrade.sh"
/bin/zsh "$ROOT/tests/test-prior-release-upgrades.sh"
/bin/zsh "$ROOT/tests/test-install-interruption.sh"
/bin/zsh "$ROOT/tests/test-first-time-status.sh"
/bin/zsh "$ROOT/tests/test-first-time-walkthrough.sh"
print 'All focused AutoBot engineering tests passed. Release media review and actual packaged/downloaded acceptance are separate gates.'
