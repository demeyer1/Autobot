#!/bin/zsh

set -eu
umask 077

SOURCE_ROOT="${0:A:h:h}"
TEST_ROOT="$(/usr/bin/mktemp -d -t autoassist-first-time-status-test)"
TEST_ROOT="${TEST_ROOT:A}"
TEST_HOME="$TEST_ROOT/home"
INSTALL_ROOT="$TEST_HOME/AutoAssist"
OUTPUT_ROOT="$TEST_ROOT/output"

cleanup() {
  local exit_code=$?
  if [[ -d "$TEST_ROOT" && "$TEST_ROOT" == "${TMPDIR:-/tmp}"/autoassist-first-time-status-test.* ]]; then
    /bin/rm -rf -- "$TEST_ROOT"
  fi
  return "$exit_code"
}
trap cleanup EXIT INT TERM

/bin/mkdir -p "$TEST_HOME" "$OUTPUT_ROOT"
"$SOURCE_ROOT/install.sh" \
  --destination "$INSTALL_ROOT" \
  --home-root "$TEST_HOME" \
  --instance-id firsttimestatus \
  --test-mode \
  --test-root "$TEST_ROOT" \
  --skip-launch-agent > "$OUTPUT_ROOT/install.log"
TEST_HOME="${TEST_HOME:A}"
INSTALL_ROOT="${INSTALL_ROOT:A}"

STATUS_WRITER="$INSTALL_ROOT/skills/first-time/scripts/write-status.sh"
SETUP_VALIDATOR="$INSTALL_ROOT/skills/first-time/scripts/validate-setup.sh"
PROGRESS="$INSTALL_ROOT/skills/first-time/scripts/walkthrough-progress.sh"
PROJECTS_FILE="$INSTALL_ROOT/PROJECTS.md"
STATUS_FILE="$INSTALL_ROOT/01_PROJECTS/first-time/STATUS.md"
MARKER="$INSTALL_ROOT/.install-state/first-time-complete"

projects_hash_initial="$(/usr/bin/shasum -a 256 "$PROJECTS_FILE" | /usr/bin/awk '{print $1}')"
/bin/ln -s "$TEST_ROOT/missing-first-time-marker-target" "$MARKER"
if [[ ! -L "$MARKER" || -e "$MARKER" ]]; then
  /bin/echo "first-time status regression did not create a dangling marker symlink fixture" >&2
  exit 1
fi
if "$STATUS_WRITER" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --state pending > "$OUTPUT_ROOT/pending-with-dangling-marker.log" 2>&1; then
  /bin/echo "pending status was accepted while a dangling completion-marker symlink existed" >&2
  exit 1
fi
if [[ "$projects_hash_initial" != "$(/usr/bin/shasum -a 256 "$PROJECTS_FILE" | /usr/bin/awk '{print $1}')" \
  || -e "$STATUS_FILE" || -L "$STATUS_FILE" ]]; then
  /bin/echo "rejected dangling-marker status changed a generated status surface" >&2
  exit 1
fi
/bin/unlink "$MARKER"

/bin/cp -p "$PROJECTS_FILE" "$OUTPUT_ROOT/projects-before-invalid-markers.md"
print -r -- '<!-- AUTOASSIST FIRST-TIME STATUS END -->' >> "$PROJECTS_FILE"
print -r -- '<!-- AUTOASSIST FIRST-TIME STATUS START -->' >> "$PROJECTS_FILE"
invalid_markers_hash="$(/usr/bin/shasum -a 256 "$PROJECTS_FILE" | /usr/bin/awk '{print $1}')"
if "$STATUS_WRITER" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --state pending > "$OUTPUT_ROOT/pending-with-reversed-markers.log" 2>&1; then
  /bin/echo "pending status was accepted with reversed managed status delimiters" >&2
  exit 1
fi
if [[ "$invalid_markers_hash" != "$(/usr/bin/shasum -a 256 "$PROJECTS_FILE" | /usr/bin/awk '{print $1}')" \
  || -e "$STATUS_FILE" || -L "$STATUS_FILE" ]]; then
  /bin/echo "rejected reversed-marker status changed a generated status surface" >&2
  exit 1
fi
/bin/cp -p "$OUTPUT_ROOT/projects-before-invalid-markers.md" "$PROJECTS_FILE"

"$STATUS_WRITER" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --state pending > "$OUTPUT_ROOT/pending.log"
if [[ -e "$MARKER" ]]; then
  /bin/echo "pending status writer created a completion marker" >&2
  exit 1
fi
/usr/bin/grep -F -q 'setup is incomplete' "$PROJECTS_FILE"
/usr/bin/grep -F -q 'Setup is incomplete.' "$STATUS_FILE"
/usr/bin/grep -F -q 'completion marker remain pending' "$STATUS_FILE"

/bin/mkdir -p "$INSTALL_ROOT/01_PROJECTS/unrelated-user-project"
/usr/bin/printf '%s\n' 'unrelated user project sentinel' > "$INSTALL_ROOT/01_PROJECTS/unrelated-user-project/STATUS.md"
/usr/bin/printf '%s\n' '' '- [Unrelated user project](01_PROJECTS/unrelated-user-project/STATUS.md): active.' >> "$PROJECTS_FILE"
unrelated_status_hash_before="$(/usr/bin/shasum -a 256 "$INSTALL_ROOT/01_PROJECTS/unrelated-user-project/STATUS.md" | /usr/bin/awk '{print $1}')"

/usr/bin/printf '%s\n' \
  'AUTOASSIST_USER_LABEL=Status Test Owner' \
  "AUTOASSIST_HOME=$INSTALL_ROOT" \
  'CHATGPT_ACCOUNT_LABEL=Status Test ChatGPT' \
  'DEFAULT_BROWSER_LABEL=Test Browser' \
  'DEFAULT_BROWSER_PROFILE_LABEL=Test Profile' \
  'DEFAULT_DESTINATION_LABEL=Local AutoAssist Project' \
  'PRIVACY_MODE=separate-zones' \
  'TERMINAL_UPDATES=chatgpt' > "$INSTALL_ROOT/config/profile.conf"

/usr/bin/printf '%s\n' \
  'SETUP_VERSION=1' \
  'DEDICATED_LAPTOP_READY=yes' \
  'CHATGPT_SIGN_IN_METHOD=already-signed-in' \
  'CHATGPT_SIGN_IN_CONFIRMED=yes' \
  'REQUESTED_CAPABILITIES=' \
  'NATIVE_PROJECT_STATE=unavailable' \
  'NATIVE_COMPUTER_USE_STATE=not-requested' \
  'NATIVE_VOICE_STATE=not-requested' \
  'NATIVE_APP_AUTOMATION_STATE=not-requested' \
  'NATIVE_GOAL_STATE=not-requested' \
  'PERMISSION_MICROPHONE=deferred-not-needed' \
  'PERMISSION_SCREEN_RECORDING=deferred-not-needed' \
  'PERMISSION_ACCESSIBILITY=deferred-not-needed' \
  'PERMISSION_AUTOMATION=deferred-not-needed' \
  'PERMISSION_FILES_AND_FOLDERS=deferred-not-needed' \
  'ACTIVE_PRIVACY_ZONES=PRIVATE,FAMILY_FRIENDS,WORK' \
  'SHARED_ZONE_OPT_IN=no' \
  'TONE_LEARNING=disabled' \
  'TONE_PROFILE_IDS=' \
  'RAW_MESSAGE_RETENTION=disabled' \
  'CONNECTOR_WRITE_MODE=read-only' \
  'EXTERNAL_WRITE_POLICY=first-party-rendered-only' \
  'NO_ATTRIBUTION_POLICY=fail-closed' \
  'NATIVE_GOAL_PERSISTENCE=required' > "$INSTALL_ROOT/config/first-time.conf"
/bin/chmod 600 "$INSTALL_ROOT/config/profile.conf" "$INSTALL_ROOT/config/first-time.conf"

"$SETUP_VALIDATOR" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --smoke > "$OUTPUT_ROOT/smoke.log"
SMOKE_OBJECTIVE_ID="$(/usr/bin/awk -F= '$1 == "SMOKE_OBJECTIVE_ID" { print $2; exit }' "$OUTPUT_ROOT/smoke.log")"
if [[ -z "$SMOKE_OBJECTIVE_ID" ]]; then
  /bin/echo "first-time status regression did not obtain a smoke objective ID" >&2
  exit 1
fi

"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage independent-review --status ready-for-review --gate none \
  --evidence local-smoke-readback --smoke-objective "$SMOKE_OBJECTIVE_ID" > "$OUTPUT_ROOT/review-ready.log"
"$STATUS_WRITER" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --state pending > "$OUTPUT_ROOT/pending-after-smoke.log"
/usr/bin/grep -F -q 'The local setup smoke is complete' "$STATUS_FILE"
/usr/bin/grep -F -q 'independent read-only validation' "$STATUS_FILE"
/usr/bin/grep -F -q "$SMOKE_OBJECTIVE_ID" "$STATUS_FILE"
if /usr/bin/grep -F -q 'Complete the local setup smoke objective.' "$STATUS_FILE"; then
  /bin/echo "pending first-time status told a resumed user to repeat a validated smoke" >&2
  exit 1
fi

SMOKE_EVIDENCE_DIR="$INSTALL_ROOT/03_OUTPUTS/.first-time-smoke/$SMOKE_OBJECTIVE_ID"
SMOKE_STAGE_EVIDENCE="$SMOKE_EVIDENCE_DIR/rendered_readback_verified.txt"
/bin/mv "$SMOKE_STAGE_EVIDENCE" "$OUTPUT_ROOT/smoke-stage-missing.txt"
if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/missing-smoke-show.log" 2>&1; then
  /bin/echo "walkthrough reported review readiness after smoke evidence was removed" >&2
  exit 1
fi
"$STATUS_WRITER" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --state pending > "$OUTPUT_ROOT/pending-after-missing-smoke.log"
/usr/bin/grep -F -q 'Setup is incomplete.' "$STATUS_FILE"
if /usr/bin/grep -F -q 'The local setup smoke is complete' "$STATUS_FILE"; then
  /bin/echo "pending status claimed smoke completion after evidence was removed" >&2
  exit 1
fi
/bin/mv "$OUTPUT_ROOT/smoke-stage-missing.txt" "$SMOKE_STAGE_EVIDENCE"

/bin/cp -p "$SMOKE_STAGE_EVIDENCE" "$OUTPUT_ROOT/smoke-stage-original.txt"
/usr/bin/printf '%s\n' \
  "objective_id=$SMOKE_OBJECTIVE_ID" \
  'stage=rendered_readback_verified' \
  'external_mutation=true' > "$SMOKE_STAGE_EVIDENCE"
/bin/chmod 600 "$SMOKE_STAGE_EVIDENCE"
if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/corrupt-smoke-show.log" 2>&1; then
  /bin/echo "walkthrough reported review readiness with corrupt smoke evidence" >&2
  exit 1
fi
"$STATUS_WRITER" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --state pending > "$OUTPUT_ROOT/pending-after-corrupt-smoke.log"
/usr/bin/grep -F -q 'Setup is incomplete.' "$STATUS_FILE"
if /usr/bin/grep -F -q 'The local setup smoke is complete' "$STATUS_FILE"; then
  /bin/echo "pending status claimed smoke completion with corrupt evidence" >&2
  exit 1
fi
/bin/mv "$OUTPUT_ROOT/smoke-stage-original.txt" "$SMOKE_STAGE_EVIDENCE"

SETUP_HASH="$(/usr/bin/shasum -a 256 "$INSTALL_ROOT/config/first-time.conf" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s\n' \
  'SETUP_VERSION=1' \
  "COMPLETED_AT=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" \
  'VALIDATOR_LABEL=independent-status-fixture-validator' \
  "SETUP_CONFIG_SHA256=$SETUP_HASH" \
  "SMOKE_OBJECTIVE_ID=$SMOKE_OBJECTIVE_ID" > "$MARKER"
/bin/chmod 600 "$MARKER"

"$STATUS_WRITER" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --state complete > "$OUTPUT_ROOT/complete.log"
/usr/bin/grep -F -q 'setup validation passed' "$PROJECTS_FILE"
/usr/bin/grep -F -q 'Setup validation passed.' "$STATUS_FILE"
/usr/bin/grep -F -q 'completion marker is present and current' "$PROJECTS_FILE"
/usr/bin/grep -F -q 'Unrelated user project' "$PROJECTS_FILE"
if /usr/bin/grep -Eiq 'ready_for_validation|marker (is )?absent|validation (is )?pending' "$PROJECTS_FILE" "$STATUS_FILE"; then
  /bin/echo "completed first-time status retained stale pending language" >&2
  exit 1
fi

projects_hash_complete="$(/usr/bin/shasum -a 256 "$PROJECTS_FILE" | /usr/bin/awk '{print $1}')"
status_hash_complete="$(/usr/bin/shasum -a 256 "$STATUS_FILE" | /usr/bin/awk '{print $1}')"
"$STATUS_WRITER" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --state complete > "$OUTPUT_ROOT/complete-idempotent.log"
if [[ "$projects_hash_complete" != "$(/usr/bin/shasum -a 256 "$PROJECTS_FILE" | /usr/bin/awk '{print $1}')" \
  || "$status_hash_complete" != "$(/usr/bin/shasum -a 256 "$STATUS_FILE" | /usr/bin/awk '{print $1}')" ]]; then
  /bin/echo "complete status reconciliation is not idempotent" >&2
  exit 1
fi

if "$STATUS_WRITER" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --state pending > "$OUTPUT_ROOT/pending-with-marker.log" 2>&1; then
  /bin/echo "pending status was accepted while the completion marker existed" >&2
  exit 1
fi
if [[ "$projects_hash_complete" != "$(/usr/bin/shasum -a 256 "$PROJECTS_FILE" | /usr/bin/awk '{print $1}')" \
  || "$status_hash_complete" != "$(/usr/bin/shasum -a 256 "$STATUS_FILE" | /usr/bin/awk '{print $1}')" ]]; then
  /bin/echo "rejected pending status changed a completed status surface" >&2
  exit 1
fi

"$SOURCE_ROOT/install.sh" \
  --destination "$INSTALL_ROOT" \
  --home-root "$TEST_HOME" \
  --instance-id firsttimestatus \
  --target-quiescent \
  --test-mode \
  --test-root "$TEST_ROOT" \
  --skip-launch-agent > "$OUTPUT_ROOT/reinstall.log"

unrelated_status_hash_after="$(/usr/bin/shasum -a 256 "$INSTALL_ROOT/01_PROJECTS/unrelated-user-project/STATUS.md" | /usr/bin/awk '{print $1}')"
if [[ "$unrelated_status_hash_before" != "$unrelated_status_hash_after" ]]; then
  /bin/echo "managed reinstall changed unrelated project content" >&2
  exit 1
fi
if [[ "$projects_hash_complete" != "$(/usr/bin/shasum -a 256 "$PROJECTS_FILE" | /usr/bin/awk '{print $1}')" \
  || "$status_hash_complete" != "$(/usr/bin/shasum -a 256 "$STATUS_FILE" | /usr/bin/awk '{print $1}')" ]]; then
  /bin/echo "managed reinstall changed the reconciled first-time status surfaces" >&2
  exit 1
fi
if [[ "$(/usr/bin/awk 'index($0, "](01_PROJECTS/first-time/STATUS.md):") > 0 { count += 1 } END { print count + 0 }' "$PROJECTS_FILE")" != "1" ]]; then
  /bin/echo "managed reinstall left a duplicate or missing first-time command-center entry" >&2
  exit 1
fi
if /usr/bin/grep -Eiq 'ready_for_validation|marker (is )?absent|validation (is )?pending' "$PROJECTS_FILE" "$STATUS_FILE"; then
  /bin/echo "managed reinstall reintroduced stale pending language" >&2
  exit 1
fi

/bin/echo "First-time status reconciliation and managed reinstall regression passed."
