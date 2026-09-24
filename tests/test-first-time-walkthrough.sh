#!/bin/zsh

set -eu
umask 077

SOURCE_ROOT="${0:A:h:h}"
TEST_ROOT="$(/usr/bin/mktemp -d -t autoassist-first-time-walkthrough-test)"
TEST_ROOT="${TEST_ROOT:A}"
TEST_HOME="$TEST_ROOT/account home"
INSTALL_ROOT="$TEST_HOME/AutoAssist"
OUTPUT_ROOT="$TEST_ROOT/output"

cleanup() {
  local exit_code=$?
  if [[ -d "$TEST_ROOT" && "$TEST_ROOT" == "${TMPDIR:-/tmp}"/autoassist-first-time-walkthrough-test.* ]]; then
    /bin/rm -rf -- "$TEST_ROOT"
  fi
  return "$exit_code"
}
trap cleanup EXIT INT TERM

/bin/mkdir -p "$TEST_HOME" "$OUTPUT_ROOT"
"$SOURCE_ROOT/install.sh" \
  --destination "$INSTALL_ROOT" \
  --home-root "$TEST_HOME" \
  --instance-id walkthrough \
  --test-mode \
  --test-root "$TEST_ROOT" \
  --skip-launch-agent > "$OUTPUT_ROOT/install.log"

PROGRESS="$INSTALL_ROOT/skills/first-time/scripts/walkthrough-progress.sh"
VALIDATOR="$INSTALL_ROOT/skills/first-time/scripts/validate-setup.sh"
STATE="$INSTALL_ROOT/.install-state/first-time-progress"
MARKER="$INSTALL_ROOT/.install-state/first-time-complete"
SIBLING="$TEST_HOME/sibling-sentinel"

"$PROGRESS" --help > "$OUTPUT_ROOT/progress-help.log"
/usr/bin/grep -F -q 'STAGE:    installed | project-primary | local-configuration | native-capabilities | local-smoke | independent-review | complete' "$OUTPUT_ROOT/progress-help.log"
/usr/bin/grep -F -q 'STATUS:   active | waiting-user | pending-capability | ready-for-review | complete' "$OUTPUT_ROOT/progress-help.log"
/usr/bin/grep -F -q -- '--stage independent-review --status ready-for-review' "$OUTPUT_ROOT/progress-help.log"
/usr/bin/grep -F -q 'references/setup-workflow.md' "$OUTPUT_ROOT/progress-help.log"
/usr/bin/grep -F -q 'references/setup-workflow.md#5-seal-and-reread' "$INSTALL_ROOT/skills/first-time/SKILL.md"
/usr/bin/grep -F -q 'setup-workflow.md#5-seal-and-reread' "$INSTALL_ROOT/skills/first-time/references/operator-walkthrough.md"
/usr/bin/printf 'preserve sibling\n' > "$SIBLING"
SIBLING_HASH="$(/usr/bin/shasum -a 256 "$SIBLING" | /usr/bin/awk '{print $1}')"

/bin/mv "$INSTALL_ROOT/.install-state/receipt.json" "$OUTPUT_ROOT/receipt.json"
/bin/mv "$INSTALL_ROOT/runtime/lib/install-common.sh" "$OUTPUT_ROOT/install-common.sh"
/usr/bin/printf '#!/bin/zsh\n/usr/bin/touch "%s"\n' "$SIBLING.injected" > "$INSTALL_ROOT/runtime/lib/install-common.sh"
/bin/chmod 700 "$INSTALL_ROOT/runtime/lib/install-common.sh"
if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/missing-receipt.log" 2>&1; then
  /bin/echo "walkthrough accepted a managed marker without its receipt" >&2
  exit 1
fi
[[ ! -e "$SIBLING.injected" && ! -L "$SIBLING.injected" ]] || { /bin/echo "walkthrough sourced installation code before receipt validation" >&2; exit 1; }
/bin/mv "$OUTPUT_ROOT/install-common.sh" "$INSTALL_ROOT/runtime/lib/install-common.sh"
/bin/mv "$OUTPUT_ROOT/receipt.json" "$INSTALL_ROOT/.install-state/receipt.json"
if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_ROOT" show > "$OUTPUT_ROOT/wrong-account-home.log" 2>&1; then
  /bin/echo "walkthrough accepted an account home that did not match its receipt" >&2
  exit 1
fi
/bin/ln -s "$TEST_HOME" "$TEST_ROOT/account-alias"
if "$PROGRESS" --root "$TEST_ROOT/account-alias/AutoAssist" --account-home "$TEST_ROOT" show > "$OUTPUT_ROOT/symlink-ancestor.log" 2>&1; then
  /bin/echo "walkthrough accepted a lexical symlink ancestor" >&2
  exit 1
fi

"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/not-started.json"
/usr/bin/grep -F -q '"status":"not-started"' "$OUTPUT_ROOT/not-started.json"

if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage project-primary --status waiting-user --gate project-primary --evidence none > "$OUTPUT_ROOT/forged-gate.log" 2>&1; then
  /bin/echo "walkthrough accepted a user gate without fresh readable evidence" >&2
  exit 1
fi

"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage project-primary --status waiting-user --gate project-primary --evidence fresh-readable-gate > "$OUTPUT_ROOT/project-gate.log"
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage project-primary --status waiting-user --gate project-primary --evidence fresh-readable-gate > "$OUTPUT_ROOT/project-gate-idempotent.log"
if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage project-primary --status active --gate none --evidence installed-receipt > "$OUTPUT_ROOT/bad-same-phase-clear.log" 2>&1; then
  /bin/echo "walkthrough cleared a user gate without fresh post-gate readback" >&2
  exit 1
fi
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage installed --status active --gate none --evidence installed-receipt > "$OUTPUT_ROOT/backward-reentry.log"
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/retained-after-backward.json"
/usr/bin/grep -F -q '"stage":"project-primary"' "$OUTPUT_ROOT/retained-after-backward.json"
/usr/bin/grep -F -q '"waiting_gate":"project-primary"' "$OUTPUT_ROOT/retained-after-backward.json"
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage local-configuration --status active --gate none --evidence local-config-readback > "$OUTPUT_ROOT/later-local-work.log"
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/retained-gate.json"
/usr/bin/grep -F -q '"stage":"project-primary"' "$OUTPUT_ROOT/retained-gate.json"
/usr/bin/grep -F -q '"status":"waiting-user"' "$OUTPUT_ROOT/retained-gate.json"
/usr/bin/grep -F -q '"waiting_gate":"project-primary"' "$OUTPUT_ROOT/retained-gate.json"

"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage project-primary --status active --gate none --evidence fresh-post-gate-readback > "$OUTPUT_ROOT/project-resumed.log"

/usr/bin/printf '%s\n' \
  'AUTOASSIST_USER_LABEL=Local User' \
  "AUTOASSIST_HOME=$INSTALL_ROOT" \
  'CHATGPT_ACCOUNT_LABEL=not-configured' \
  'DEFAULT_BROWSER_LABEL=Observed Local Browser' \
  'DEFAULT_BROWSER_PROFILE_LABEL=Observed Local Profile' \
  'DEFAULT_DESTINATION_LABEL=Local AutoAssist Project' \
  'PRIVACY_MODE=separate-zones' \
  'TERMINAL_UPDATES=chatgpt' > "$INSTALL_ROOT/config/profile.conf"
/usr/bin/printf '%s\n' \
  'SETUP_VERSION=1' \
  'DEDICATED_LAPTOP_READY=local-only' \
  'CHATGPT_SIGN_IN_METHOD=not-configured' \
  'CHATGPT_SIGN_IN_CONFIRMED=no' \
  'REQUESTED_CAPABILITIES=' \
  'NATIVE_PROJECT_STATE=unavailable' \
  'NATIVE_COMPUTER_USE_STATE=unavailable' \
  'NATIVE_VOICE_STATE=not-requested' \
  'NATIVE_APP_AUTOMATION_STATE=not-requested' \
  'NATIVE_GOAL_STATE=not-requested' \
  'PERMISSION_MICROPHONE=deferred-not-needed' \
  'PERMISSION_SCREEN_RECORDING=deferred-not-needed' \
  'PERMISSION_ACCESSIBILITY=deferred-not-needed' \
  'PERMISSION_AUTOMATION=deferred-not-needed' \
  'PERMISSION_FILES_AND_FOLDERS=deferred-not-needed' \
  'ACTIVE_PRIVACY_ZONES=PRIVATE' \
  'SHARED_ZONE_OPT_IN=no' \
  'TONE_LEARNING=disabled' \
  'TONE_PROFILE_IDS=' \
  'RAW_MESSAGE_RETENTION=disabled' \
  'CONNECTOR_WRITE_MODE=read-only' \
  'EXTERNAL_WRITE_POLICY=first-party-rendered-only' \
  'NO_ATTRIBUTION_POLICY=fail-closed' \
  'NATIVE_GOAL_PERSISTENCE=required' > "$INSTALL_ROOT/config/first-time.conf"
/bin/chmod 600 "$INSTALL_ROOT/config/profile.conf" "$INSTALL_ROOT/config/first-time.conf"

"$VALIDATOR" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" > "$OUTPUT_ROOT/accountless-validation.log"
/usr/bin/grep -F -q 'accountless sign-in state' "$OUTPUT_ROOT/accountless-validation.log"
/usr/bin/grep -F -q 'no optional capabilities requested' "$OUTPUT_ROOT/accountless-validation.log"
/usr/bin/grep -F -q 'explicit local-only route' "$OUTPUT_ROOT/accountless-validation.log"

/bin/cp -p "$INSTALL_ROOT/config/first-time.conf" "$OUTPUT_ROOT/local-only-config"
/usr/bin/perl -0pi -e 's/^NATIVE_PROJECT_STATE=unavailable$/NATIVE_PROJECT_STATE=manual-primary-required/m' "$INSTALL_ROOT/config/first-time.conf"
if "$VALIDATOR" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" > "$OUTPUT_ROOT/manual-primary-pending.log" 2>&1; then
  /bin/echo "walkthrough validator accepted a pending native primary-Project step" >&2
  exit 1
fi
/bin/cp -p "$OUTPUT_ROOT/local-only-config" "$INSTALL_ROOT/config/first-time.conf"

/bin/cp -p "$INSTALL_ROOT/config/first-time.conf" "$OUTPUT_ROOT/pre-synthetic-capability-config"
/usr/bin/perl -0pi -e 's/^REQUESTED_CAPABILITIES=$/REQUESTED_CAPABILITIES=computer-use/m; s/^NATIVE_COMPUTER_USE_STATE=unavailable$/NATIVE_COMPUTER_USE_STATE=available/m; s/^PERMISSION_SCREEN_RECORDING=deferred-not-needed$/PERMISSION_SCREEN_RECORDING=observed-effective/m; s/^PERMISSION_ACCESSIBILITY=deferred-not-needed$/PERMISSION_ACCESSIBILITY=observed-effective/m' "$INSTALL_ROOT/config/first-time.conf"
/usr/bin/printf 'SIMULATION_ONLY=schema acceptance; no native app or permission was exercised\n' > "$OUTPUT_ROOT/synthetic-capability-scope.txt"
"$VALIDATOR" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" > "$OUTPUT_ROOT/synthetic-observed-effective-schema.log"
/usr/bin/grep -F -q 'computer-use has current effective accessibility access' "$OUTPUT_ROOT/synthetic-observed-effective-schema.log"
/bin/cp -p "$OUTPUT_ROOT/pre-synthetic-capability-config" "$INSTALL_ROOT/config/first-time.conf"

"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage native-capabilities --status pending-capability --gate computer-use-install --evidence capability-unavailable > "$OUTPUT_ROOT/unavailable.log"
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage local-smoke --status active --gate none --evidence doctor-readback > "$OUTPUT_ROOT/local-after-unavailable.log"
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/retained-unavailable.json"
/usr/bin/grep -F -q '"stage":"native-capabilities"' "$OUTPUT_ROOT/retained-unavailable.json"
/usr/bin/grep -F -q '"waiting_gate":"computer-use-install"' "$OUTPUT_ROOT/retained-unavailable.json"

if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage complete --status complete --gate none --evidence marker-readback > "$OUTPUT_ROOT/forged-complete.log" 2>&1; then
  /bin/echo "walkthrough accepted completion without its current marker" >&2
  exit 1
fi

/bin/cp -p "$STATE" "$OUTPUT_ROOT/progress-safe"
/bin/rm -f "$STATE"
/bin/ln -s "$SIBLING" "$STATE"
if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage native-capabilities --status active --gate none --evidence fresh-post-gate-readback > "$OUTPUT_ROOT/symlink-state.log" 2>&1; then
  /bin/echo "walkthrough accepted a symlinked progress destination" >&2
  exit 1
fi
[[ "$SIBLING_HASH" == "$(/usr/bin/shasum -a 256 "$SIBLING" | /usr/bin/awk '{print $1}')" ]] || { /bin/echo "rejected progress write changed a sibling" >&2; exit 1; }
/bin/unlink "$STATE"
/bin/cp -p "$OUTPUT_ROOT/progress-safe" "$STATE"

/usr/bin/perl -0pi -e 's/^ROOT_SHA256=.*/ROOT_SHA256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff/m' "$STATE"
if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/wrong-root.log" 2>&1; then
  /bin/echo "walkthrough accepted a wrong-root progress record" >&2
  exit 1
fi
/bin/cp -p "$OUTPUT_ROOT/progress-safe" "$STATE"

"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage native-capabilities --status active --gate none --evidence fresh-post-gate-readback > "$OUTPUT_ROOT/capability-resumed.log"
"$VALIDATOR" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --smoke > "$OUTPUT_ROOT/smoke.log"
SMOKE_OBJECTIVE_ID="$(/usr/bin/awk -F= '$1 == "SMOKE_OBJECTIVE_ID" { print $2; exit }' "$OUTPUT_ROOT/smoke.log")"
[[ -n "$SMOKE_OBJECTIVE_ID" ]] || { /bin/echo "walkthrough smoke returned no objective ID" >&2; exit 1; }
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage independent-review --status ready-for-review --gate none --evidence local-smoke-readback --smoke-objective "$SMOKE_OBJECTIVE_ID" > "$OUTPUT_ROOT/review-ready.log"

/bin/cp -p "$INSTALL_ROOT/config/first-time.conf" "$OUTPUT_ROOT/config-before-review-drift"
/usr/bin/printf '# drift before review\n' >> "$INSTALL_ROOT/config/first-time.conf"
if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/stale-review-ready.log" 2>&1; then
  /bin/echo "walkthrough reported review readiness after configuration drift" >&2
  exit 1
fi
/bin/cp -p "$OUTPUT_ROOT/config-before-review-drift" "$INSTALL_ROOT/config/first-time.conf"

SETUP_HASH="$(/usr/bin/shasum -a 256 "$INSTALL_ROOT/config/first-time.conf" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s\n' \
  'SETUP_VERSION=1' \
  "COMPLETED_AT=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" \
  'VALIDATOR_LABEL=independent-walkthrough-fixture-validator' \
  "SETUP_CONFIG_SHA256=$SETUP_HASH" \
  "SMOKE_OBJECTIVE_ID=$SMOKE_OBJECTIVE_ID" > "$MARKER"
/bin/chmod 600 "$MARKER"
"$VALIDATOR" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --require-marker > "$OUTPUT_ROOT/marker-readback.log"
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage complete --status complete --gate none --evidence marker-readback --smoke-objective "$SMOKE_OBJECTIVE_ID" > "$OUTPUT_ROOT/complete.log"
"$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/complete.json"
/usr/bin/grep -F -q '"status":"complete"' "$OUTPUT_ROOT/complete.json"

/bin/mv "$MARKER" "$OUTPUT_ROOT/marker"
if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" show > "$OUTPUT_ROOT/forged-complete-show.log" 2>&1; then
  /bin/echo "walkthrough reported completion without its marker" >&2
  exit 1
fi
/bin/mv "$OUTPUT_ROOT/marker" "$MARKER"

if "$PROGRESS" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" record \
  --stage native-capabilities --status active --gate none --evidence native-capability-readback > "$OUTPUT_ROOT/reopen-complete.log" 2>&1; then
  /bin/echo "walkthrough reopened a current completed setup" >&2
  exit 1
fi

/usr/bin/printf '\n# current user choice\n' >> "$INSTALL_ROOT/config/first-time.conf"
if "$VALIDATOR" --root "$INSTALL_ROOT" --account-home "$TEST_HOME" --require-marker > "$OUTPUT_ROOT/stale-marker.log" 2>&1; then
  /bin/echo "walkthrough validator accepted changed configuration with a stale marker" >&2
  exit 1
fi

/bin/echo "First-time active walkthrough state, accountless defaults and completion-gate regressions passed."
