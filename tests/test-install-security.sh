#!/bin/zsh
set -eu
umask 077
SOURCE_ROOT="${0:A:h:h}"
TEMP_PARENT="${TMPDIR:-/tmp}"; TEMP_PARENT="${TEMP_PARENT%/}"
TEST_ROOT="$(/usr/bin/mktemp -d "$TEMP_PARENT/autoassist-install-security.XXXXXX")"
TEST_ROOT="${TEST_ROOT:A}"
ACCOUNT_HOME="$TEST_ROOT/home"
cleanup() { local s=$?; [[ -d "$TEST_ROOT" ]] && /bin/rm -rf "$TEST_ROOT"; return "$s"; }
trap cleanup EXIT INT TERM
/bin/mkdir -p "$ACCOUNT_HOME"
receipt_line="$(/usr/bin/grep -n '/bin/mv -f "$RECEIPT_TEMP"' "$SOURCE_ROOT/install.sh" | /usr/bin/cut -d: -f1)"
bootstrap_line="$(/usr/bin/grep -n -F '/bin/launchctl bootstrap "$GUI_DOMAIN" "$PLIST_PATH"' "$SOURCE_ROOT/install.sh" | /usr/bin/cut -d: -f1)"
[[ "$receipt_line" == <-> && "$bootstrap_line" == <-> && "$receipt_line" -lt "$bootstrap_line" ]] || { /bin/echo "service activation precedes receipt persistence" >&2; exit 1; }
if /usr/bin/grep -F -q '/bin/launchctl kickstart' "$SOURCE_ROOT/install.sh"; then /bin/echo "redundant service kickstart remains" >&2; exit 1; fi
/usr/bin/grep -F -q '"state_schema":2' "$SOURCE_ROOT/install.sh"
if "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$ACCOUNT_HOME/reject" --skip-launch-agent --failpoint after-old-rename > "$TEST_ROOT/prod-failpoint.log" 2>&1; then /bin/echo "production failpoint accepted" >&2; exit 1; fi
/bin/ln -s "$TEST_ROOT" "$ACCOUNT_HOME/link"
if "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$ACCOUNT_HOME/link/AutoAssist" --skip-launch-agent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/symlink.log" 2>&1; then /bin/echo "symlink destination accepted" >&2; exit 1; fi
/bin/rm "$ACCOUNT_HOME/link"
SERVICE_HOME="$TEST_ROOT/service-home"
/bin/mkdir -p "$SERVICE_HOME/Library/LaunchAgents"
/usr/bin/printf 'unowned\n' > "$SERVICE_HOME/Library/LaunchAgents/io.autoprod.autobot.collision.plist"
if "$SOURCE_ROOT/install.sh" --home-root "$SERVICE_HOME" --destination "$SERVICE_HOME/AutoAssist" --instance-id collision --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/plist-collision.log" 2>&1; then /bin/echo "unowned same-instance plist was replaced" >&2; exit 1; fi
[[ ! -e "$SERVICE_HOME/AutoAssist" ]]
SYMLINK_HOME="$TEST_ROOT/symlink-home"
/bin/mkdir -p "$SYMLINK_HOME"
/bin/ln -s "$TEST_ROOT" "$SYMLINK_HOME/Library"
if "$SOURCE_ROOT/install.sh" --home-root "$SYMLINK_HOME" --destination "$SYMLINK_HOME/AutoAssist" --instance-id ancestor --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/launchagent-ancestor.log" 2>&1; then /bin/echo "symlinked LaunchAgents ancestor was accepted" >&2; exit 1; fi
[[ ! -e "$SYMLINK_HOME/AutoAssist" ]]
FIXTURE="$TEST_ROOT/release"
/bin/cp -Rp "$SOURCE_ROOT" "$FIXTURE"
/usr/bin/printf '../escape\n' > "$FIXTURE/config/release-allowlist.txt"
if "$FIXTURE/install.sh" --home-root "$ACCOUNT_HOME" --destination "$ACCOUNT_HOME/traversal" --skip-launch-agent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/traversal.log" 2>&1; then /bin/echo "traversal manifest accepted" >&2; exit 1; fi
[[ ! -e "$TEST_ROOT/escape" ]]
FIXTURE2="$TEST_ROOT/release-benchmark"
/bin/cp -Rp "$SOURCE_ROOT" "$FIXTURE2"
/usr/bin/printf 'benchmarks/private/runtime.js\n' > "$FIXTURE2/config/release-allowlist.txt"
/bin/mkdir -p "$FIXTURE2/benchmarks/private"
/usr/bin/touch "$FIXTURE2/benchmarks/private/runtime.js"
if "$FIXTURE2/install.sh" --home-root "$ACCOUNT_HOME" --destination "$ACCOUNT_HOME/benchmark" --skip-launch-agent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/benchmark.log" 2>&1; then /bin/echo "benchmark runtime material accepted" >&2; exit 1; fi
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$ACCOUNT_HOME/special" --instance-id specialfixture --skip-launch-agent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/special-install.log"
/bin/ln -s "$TEST_ROOT" "$ACCOUNT_HOME/.AutoAssist-backups"
if AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$ACCOUNT_HOME/special" --instance-id specialfixture --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/backup-ancestor.log" 2>&1; then /bin/echo "symlinked backup ancestor was accepted" >&2; exit 1; fi
/bin/rm "$ACCOUNT_HOME/.AutoAssist-backups"
/usr/bin/mkfifo "$ACCOUNT_HOME/special/user-fifo"
if AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$ACCOUNT_HOME/special" --instance-id specialfixture --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/special.log" 2>&1; then /bin/echo "special file accepted" >&2; exit 1; fi
/bin/echo "Traversal, symlink, benchmark boundary, failpoint scope, and special-file rejection passed."
