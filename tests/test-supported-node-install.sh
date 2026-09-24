#!/bin/zsh
set -eu
umask 077

SOURCE_ROOT="${0:A:h:h}"
NODE_EXEC="$(command -v node)"
[[ "$NODE_EXEC" == /* && -x "$NODE_EXEC" ]] || { /bin/echo 'supported Node fixture unavailable' >&2; exit 2; }
node -e 'if(Number(process.versions.node.split(".")[0])<22)process.exit(1)'

TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/autoassist-supported-node.XXXXXX")"
TEST_ROOT="${TEST_ROOT:A}"
cleanup() { local test_exit=$?; [[ -d "$TEST_ROOT" ]] && /bin/rm -rf -- "$TEST_ROOT"; return "$test_exit"; }
trap cleanup EXIT INT TERM
ACCOUNT_HOME="$TEST_ROOT/Test User"
DESTINATION="$ACCOUNT_HOME/AutoAssist"
/bin/mkdir -p "$ACCOUNT_HOME"

AUTOASSIST_NODE="$NODE_EXEC" "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id supportednode --test-mode --test-root "$TEST_ROOT" >/dev/null
[[ ! -e "$ACCOUNT_HOME/Library/LaunchAgents/io.autoprod.autobot.supportednode.plist" ]]
/usr/bin/grep -F -q '"service_label":""' "$DESTINATION/.install-state/receipt.json"
DOCTOR="$(AUTOASSIST_ACCOUNT_HOME="$ACCOUNT_HOME" AUTOASSIST_NODE="$NODE_EXEC" "$DESTINATION/runtime/bin/autoassist" doctor --json)"
node -e 'const d=JSON.parse(process.argv[1]);if(d.installation_integrity!=="healthy"||d.runtime_status!=="available"||d.service_state!=="not-configured"||!d.node_path)process.exit(1)' "$DOCTOR"

CREATED="$(AUTOASSIST_ACCOUNT_HOME="$ACCOUNT_HOME" AUTOASSIST_NODE="$NODE_EXEC" "$DESTINATION/runtime/bin/autoassist" core root-create <<'JSON'
{"root_id":"synthetic-first-task","title":"Synthetic first task","intent":"Verify a local installed runtime operation.","source":"direct_user","target":{"kind":"local","destination":"03_OUTPUTS/synthetic-note.md"}}
JSON
)"
node -e 'const d=JSON.parse(process.argv[1]);if(!d.ok||d.result.id!=="synthetic-first-task")process.exit(1)' "$CREATED"
[[ -f "$DESTINATION/state/core.json" && ! -e "$DESTINATION/state/objectives" ]]
BEFORE="$(/usr/bin/shasum -a 256 "$DESTINATION/state/core.json" | /usr/bin/awk '{print $1}')"

if AUTOASSIST_ACCOUNT_HOME="$ACCOUNT_HOME" AUTOASSIST_NODE="$TEST_ROOT/no-such-node" "$DESTINATION/runtime/bin/autoassist" core read >/dev/null 2>&1; then /bin/echo 'broken configured Node unexpectedly executed' >&2; exit 1; fi
if AUTOASSIST_ACCOUNT_HOME="$ACCOUNT_HOME" AUTOASSIST_NODE=/usr/bin/true "$DESTINATION/runtime/bin/autoassist" core read >/dev/null 2>&1; then /bin/echo 'unsupported configured Node unexpectedly executed' >&2; exit 1; fi
AFTER="$(/usr/bin/shasum -a 256 "$DESTINATION/state/core.json" | /usr/bin/awk '{print $1}')"
[[ "$BEFORE" == "$AFTER" ]]
/bin/echo 'Packaged supported Node install, advanced operation, and broken/unsupported no-fallback states passed.'
