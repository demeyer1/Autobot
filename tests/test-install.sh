#!/bin/zsh
set -eu
umask 077
SOURCE_ROOT="${0:A:h:h}"
TEMP_PARENT="${TMPDIR:-/tmp}"; TEMP_PARENT="${TEMP_PARENT%/}"
TEST_ROOT="$(/usr/bin/mktemp -d "$TEMP_PARENT/autoassist-install-base.XXXXXX")"
TEST_ROOT="${TEST_ROOT:A}"
ACCOUNT_HOME="$TEST_ROOT/New User Home"
DESTINATION="$ACCOUNT_HOME/Custom AutoAssist Path"
GLOBAL_SKILL="$ACCOUNT_HOME/.codex/skills/first-time"
cleanup() { local s=$?; [[ -d "$TEST_ROOT" ]] && /bin/rm -rf "$TEST_ROOT"; return "$s"; }
trap cleanup EXIT INT TERM
/bin/mkdir -p "$ACCOUNT_HOME" "$GLOBAL_SKILL"
/usr/bin/printf 'unrelated-user-skill\n' > "$GLOBAL_SKILL/sentinel.txt"
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id basefixture --skip-launch-agent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/install.log"
[[ -f "$DESTINATION/.install-state/receipt.json" && -f "$DESTINATION/.agents/skills/first-time/.autoassist-skill" ]]
[[ "$(/usr/bin/stat -f '%Lp' "$DESTINATION/.install-state")" == 700 && "$(/usr/bin/stat -f '%Lp' "$DESTINATION/config/profile.conf")" == 600 ]]
/usr/bin/grep -F -q '"node_status":"unavailable"' "$DESTINATION/.install-state/receipt.json"
[[ -f "$GLOBAL_SKILL/sentinel.txt" ]] || { /bin/echo "unrelated global skill was changed" >&2; exit 1; }
doctor_json="$(AUTOASSIST_TEST_NODE_ABSENT=1 "$DESTINATION/runtime/lib/install-doctor.sh" "$DESTINATION" "$ACCOUNT_HOME" --json)"
[[ "$doctor_json" == *'"installation_integrity":"healthy"'* && "$doctor_json" == *'"runtime_status":"unavailable"'* ]]
/usr/bin/printf '%s\n' '#!/bin/zsh' '[[ "$1" == "--version" ]] && { echo v22.9.0; exit 0; }' 'exit 1' > "$TEST_ROOT/node-real"
/bin/chmod 700 "$TEST_ROOT/node-real"
/bin/ln -s "$TEST_ROOT/node-real" "$TEST_ROOT/node-link"
symlink_node_json="$(AUTOASSIST_NODE="$TEST_ROOT/node-link" "$DESTINATION/runtime/lib/install-doctor.sh" "$DESTINATION" "$ACCOUNT_HOME" --json)"
[[ "$symlink_node_json" == *'"runtime_status":"available"'* && "$symlink_node_json" == *'"node_path":"'"$TEST_ROOT"'/node-real"'* ]] || { /bin/echo "canonical Node symlink discovery failed" >&2; exit 1; }
replace_receipt_node() {
  /usr/bin/sed "s|\"node_path\":\"[^\"]*\"|\"node_path\":\"$1\"|" "$DESTINATION/.install-state/receipt.json" > "$DESTINATION/.install-state/receipt.json.tmp"
  /bin/chmod 600 "$DESTINATION/.install-state/receipt.json.tmp"
  /bin/mv -f "$DESTINATION/.install-state/receipt.json.tmp" "$DESTINATION/.install-state/receipt.json"
}
RECORDED_NODE="${AUTOASSIST_TEST_NODE:-$(command -v node 2>/dev/null || true)}"
[[ -n "$RECORDED_NODE" && -x "$RECORDED_NODE" ]] || { /bin/echo "focused receipt test requires a real Node executable" >&2; exit 2; }
RECORDED_NODE="${RECORDED_NODE:A}"
recorded_version="$($RECORDED_NODE --version 2>/dev/null || true)"
recorded_major="${${recorded_version#v}%%.*}"
[[ "$recorded_major" == <-> && "$recorded_major" -ge 22 ]] || { /bin/echo "focused receipt test requires Node 22 or newer" >&2; exit 2; }
/bin/mkdir -p "$TEST_ROOT/path-bin"
/bin/ln -s "$RECORDED_NODE" "$TEST_ROOT/path-bin/node"
replace_receipt_node ""
empty_receipt_json="$(PATH="$TEST_ROOT/path-bin:/usr/bin:/bin" "$DESTINATION/runtime/lib/install-doctor.sh" "$DESTINATION" "$ACCOUNT_HOME" --json)"
[[ "$empty_receipt_json" == *'"runtime_status":"available"'* && "$empty_receipt_json" == *'"node_path":"'"$RECORDED_NODE"'"'* ]] || { /bin/echo "empty receipt Node configuration did not fall back to PATH" >&2; exit 1; }
replace_receipt_node "$RECORDED_NODE"
recorded_node_json="$(PATH=/usr/bin:/bin "$DESTINATION/runtime/lib/install-doctor.sh" "$DESTINATION" "$ACCOUNT_HOME" --json)"
[[ "$recorded_node_json" == *'"runtime_status":"available"'* && "$recorded_node_json" == *'"node_path":"'"$RECORDED_NODE"'"'* ]] || { /bin/echo "receipt-selected non-PATH Node discovery failed" >&2; exit 1; }
explicit_empty_json="$(PATH=/usr/bin:/bin AUTOASSIST_NODE= "$DESTINATION/runtime/lib/install-doctor.sh" "$DESTINATION" "$ACCOUNT_HOME" --json)"
[[ "$explicit_empty_json" == *'"runtime_status":"unavailable"'* && "$explicit_empty_json" != *'"node_path":"'"$RECORDED_NODE"'"'* ]] || { /bin/echo "explicit empty Node selection fell back" >&2; exit 1; }
relative_explicit_json="$(cd "$TEST_ROOT" && PATH=/usr/bin:/bin AUTOASSIST_NODE=node-real "$DESTINATION/runtime/lib/install-doctor.sh" "$DESTINATION" "$ACCOUNT_HOME" --json)"
[[ "$relative_explicit_json" == *'"runtime_status":"unavailable"'* ]] || { /bin/echo "relative explicit Node selection was accepted" >&2; exit 1; }
replace_receipt_node node-real
relative_recorded_json="$(cd "$TEST_ROOT" && PATH=/usr/bin:/bin "$DESTINATION/runtime/lib/install-doctor.sh" "$DESTINATION" "$ACCOUNT_HOME" --json)"
[[ "$relative_recorded_json" == *'"runtime_status":"unavailable"'* ]] || { /bin/echo "relative receipt-selected Node was accepted" >&2; exit 1; }
replace_receipt_node "$TEST_ROOT/missing-recorded-node"
invalid_recorded_json="$(PATH=/usr/bin:/bin "$DESTINATION/runtime/lib/install-doctor.sh" "$DESTINATION" "$ACCOUNT_HOME" --json)"
[[ "$invalid_recorded_json" == *'"runtime_status":"unavailable"'* && "$invalid_recorded_json" != *'"node_path":"'"$RECORDED_NODE"'"'* ]] || { /bin/echo "invalid receipt-selected Node fell back to PATH" >&2; exit 1; }
/usr/bin/printf '\nuser-owned-seed-change\n' >> "$DESTINATION/PROJECTS.md"
seed_hash="$(/usr/bin/shasum -a 256 "$DESTINATION/PROJECTS.md" | /usr/bin/awk '{print $1}')"
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id basefixture --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/reinstall.log"
[[ "$seed_hash" == "$(/usr/bin/shasum -a 256 "$DESTINATION/PROJECTS.md" | /usr/bin/awk '{print $1}')" ]] || { /bin/echo "idempotent reinstall changed user seed" >&2; exit 1; }
/usr/bin/printf '\nuser project-skill customization\n' >> "$DESTINATION/.agents/skills/first-time/SKILL.md"
project_skill_hash="$(/usr/bin/shasum -a 256 "$DESTINATION/.agents/skills/first-time/SKILL.md" | /usr/bin/awk '{print $1}')"
if AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id basefixture --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/project-skill-conflict.log" 2>&1; then /bin/echo "custom project-local skill was overwritten" >&2; exit 1; fi
[[ "$project_skill_hash" == "$(/usr/bin/shasum -a 256 "$DESTINATION/.agents/skills/first-time/SKILL.md" | /usr/bin/awk '{print $1}')" && ! -e "$DESTINATION/.install-state/migration.lock" ]]
/bin/ln -s "$TEST_ROOT" "$ACCOUNT_HOME/.Trash"
if "$DESTINATION/uninstall.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --target-quiescent > "$TEST_ROOT/uninstall-symlink.log" 2>&1; then /bin/echo "symlinked Trash ancestor was accepted" >&2; exit 1; fi
[[ -d "$DESTINATION" ]]
/bin/rm "$ACCOUNT_HOME/.Trash"
/bin/mv "$ACCOUNT_HOME/.codex" "$ACCOUNT_HOME/.codex-real"
/bin/ln -s "$TEST_ROOT" "$ACCOUNT_HOME/.codex"
if "$DESTINATION/uninstall.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --target-quiescent > "$TEST_ROOT/uninstall-global-symlink.log" 2>&1; then /bin/echo "symlinked global-skill ancestor was accepted" >&2; exit 1; fi
[[ -d "$DESTINATION" ]]
/bin/rm "$ACCOUNT_HOME/.codex"
/bin/mv "$ACCOUNT_HOME/.codex-real" "$ACCOUNT_HOME/.codex"
"$DESTINATION/uninstall.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --target-quiescent > "$TEST_ROOT/uninstall.log"
[[ ! -e "$DESTINATION" ]]
trash_count="$(/usr/bin/find "$ACCOUNT_HOME/.Trash" -mindepth 1 -maxdepth 1 -type d -name 'AutoAssist-uninstalled-*-basefixture' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
[[ "$trash_count" == 1 && -f "$GLOBAL_SKILL/sentinel.txt" ]] || { /bin/echo "uninstall isolation failed" >&2; exit 1; }
/bin/echo "Base install, Node-less doctor, idempotency, isolation, and reversible uninstall passed."
