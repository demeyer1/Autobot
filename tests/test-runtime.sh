#!/bin/zsh
set -eu
SOURCE_ROOT="${0:A:h:h}"
TEST_ROOT="$(/usr/bin/mktemp -d -t autobot-runtime-test)"
TEST_ROOT="${TEST_ROOT:A}"
trap '/bin/rm -rf "$TEST_ROOT"' EXIT
APP="$TEST_ROOT/account home/Autobot Workspace"
/bin/mkdir -p "$APP/runtime" "$APP/03_OUTPUTS" "$APP/.install-state"
/bin/cp -R "$SOURCE_ROOT/runtime/bin" "$SOURCE_ROOT/runtime/core" "$APP/runtime/"
/bin/cp "$SOURCE_ROOT/VERSION" "$SOURCE_ROOT/AGENTS.md" "$APP/"
CLI="$APP/runtime/bin/autoassist"
/bin/chmod 755 "$CLI" # Release ZIP canonicalizes the CLI mode; git source does not.
"$CLI" help >/dev/null
"$CLI" version >/dev/null
[[ ! -e "$APP/state" ]]
if "$CLI" supervisor-tick --help >"$TEST_ROOT/error" 2>&1; then exit 1; fi
[[ ! -e "$APP/state" ]]
if "$CLI" objective-status one extra >"$TEST_ROOT/error" 2>&1; then exit 1; fi
[[ ! -e "$APP/state" ]]
AUTOASSIST_NODE=/no-such-node "$CLI" version >/dev/null
AUTOASSIST_NODE=/no-such-node "$CLI" help >/dev/null
if AUTOASSIST_NODE=/no-such-node "$CLI" core read >"$TEST_ROOT/error" 2>&1; then exit 1; fi
/usr/bin/grep -q runtime-unavailable "$TEST_ROOT/error"
[[ ! -e "$APP/state" ]]
AUTOASSIST_NODE=/no-such-node "$CLI" initialize-zones >/dev/null
[[ -d "$APP/00_CONTEXT/PRIVATE" && ! -e "$APP/state" ]]
"$CLI" objective-create legacy-one 'Synthetic legacy-compatible objective' >/dev/null
for stage in research_complete draft_complete destination_updated save_confirmed rendered_readback_verified; do
  /usr/bin/printf 'Synthetic %s\n' "$stage" > "$APP/03_OUTPUTS/$stage.txt"
  "$CLI" checkpoint legacy-one "$stage" "$APP/03_OUTPUTS/$stage.txt" producer >/dev/null
  if "$CLI" validate-stage legacy-one "$stage" producer >"$TEST_ROOT/error" 2>&1; then exit 1; fi
  "$CLI" validate-stage legacy-one "$stage" reviewer >/dev/null
done
"$CLI" objective-status legacy-one > "$TEST_ROOT/status.json"
node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));if(!r.result.readiness.complete)process.exit(1)' "$TEST_ROOT/status.json"
[[ ! -e "$APP/state/objectives" ]]
BEFORE="$(/usr/bin/shasum -a 256 "$APP/state/core.json")"
"$CLI" objective-status >/dev/null
"$CLI" core help >/dev/null
if "$CLI" supervisor-tick --help >/dev/null 2>&1; then exit 1; fi
AFTER="$(/usr/bin/shasum -a 256 "$APP/state/core.json")"
[[ "$BEFORE" == "$AFTER" ]]
# A real v0.1.0 source path may be supplied by the release integration harness.
# It is never downloaded, installed, scheduled, or bundled by this test.
if [[ -n "${AUTOASSIST_LEGACY_SOURCE:-}" ]]; then
  OLD="$TEST_ROOT/old-source"
  /bin/mkdir -p "$OLD/runtime"
  /bin/cp -R "$AUTOASSIST_LEGACY_SOURCE/runtime/bin" "$AUTOASSIST_LEGACY_SOURCE/runtime/lib" "$OLD/runtime/"
  /bin/zsh "$OLD/runtime/bin/autoassist" objective-create imported-one 'Actual old public runtime objective' >/dev/null
  /bin/cp -R "$OLD/state/objectives" "$APP/state/"
  IMPORT_BEFORE="$(/usr/bin/shasum -a 256 "$APP/state/objectives/imported-one/title")"
  "$CLI" core legacy-import > "$TEST_ROOT/import.json"
  "$CLI" objective-status imported-one > "$TEST_ROOT/import-status.json"
  [[ "$IMPORT_BEFORE" == "$(/usr/bin/shasum -a 256 "$APP/state/objectives/imported-one/title")" ]]
  node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));if(!r.result.root.legacy_compatibility||r.result.root.id!=="imported-one")process.exit(1)' "$TEST_ROOT/import-status.json"
fi
/bin/echo 'PASS runtime shell, Node-unavailable base, single-store legacy CLI, and read-only inspection'
