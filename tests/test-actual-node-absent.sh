#!/bin/zsh
set -eu
umask 077

SOURCE_ROOT="${0:A:h:h}"
[[ -z "$(PATH=/usr/bin:/bin command -v node || true)" ]] || { /bin/echo 'controlled Node-free path is not Node-free' >&2; exit 2; }
TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/autoassist-node-absent.XXXXXX")"
TEST_ROOT="${TEST_ROOT:A}"
cleanup() { local test_exit=$?; [[ -d "$TEST_ROOT" ]] && /bin/rm -rf -- "$TEST_ROOT"; return "$test_exit"; }
trap cleanup EXIT INT TERM
ACCOUNT_HOME="$TEST_ROOT/No Account User"
DESTINATION="$ACCOUNT_HOME/AutoAssist"
/bin/mkdir -p "$ACCOUNT_HOME"

PATH=/usr/bin:/bin "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id nodeabsent --test-mode --test-root "$TEST_ROOT" >/dev/null
[[ ! -e "$ACCOUNT_HOME/Library/LaunchAgents/io.autoprod.autobot.nodeabsent.plist" ]]
DOCTOR="$(PATH=/usr/bin:/bin AUTOASSIST_ACCOUNT_HOME="$ACCOUNT_HOME" "$DESTINATION/runtime/bin/autoassist" doctor --json)"
node -e 'const d=JSON.parse(process.argv[1]);if(d.installation_integrity!=="healthy"||d.runtime_status!=="unavailable"||!d.service_state.startsWith("not-configured"))process.exit(1)' "$DOCTOR"
[[ "$(PATH=/usr/bin:/bin "$DESTINATION/runtime/bin/autoassist" version)" == "$(/bin/cat "$SOURCE_ROOT/VERSION")" ]]
PATH=/usr/bin:/bin "$DESTINATION/runtime/bin/autoassist" initialize-zones >/dev/null
[[ -d "$DESTINATION/00_CONTEXT/PRIVATE" && ! -e "$DESTINATION/state/core.json" ]]
if PATH=/usr/bin:/bin "$DESTINATION/runtime/bin/autoassist" core read >/dev/null 2>&1; then /bin/echo 'advanced runtime unexpectedly available' >&2; exit 1; fi
[[ ! -e "$DESTINATION/state/core.json" ]]

PATH=/usr/bin:/bin "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id nodeabsent --repair --target-quiescent --test-mode --test-root "$TEST_ROOT" >/dev/null
PATH=/usr/bin:/bin "$DESTINATION/uninstall.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --target-quiescent >/dev/null
[[ ! -e "$DESTINATION" ]]
/bin/echo 'Actual Node-free search: base install, doctor, zones, repair and uninstall passed without advanced state or service.'
