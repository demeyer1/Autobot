#!/bin/zsh

set -eu
umask 077

SCRIPT_DIR="${0:A:h}"
AUTOASSIST_ROOT="${SCRIPT_DIR:h:h:h}"
ACCOUNT_HOME="${AUTOASSIST_ACCOUNT_HOME:-${HOME:-}}"
RUN_SMOKE=0
REQUIRE_MARKER=0
FAILURES=0
SMOKE_OBJECTIVE_ID=""
TEMP_ROOT=""
STAGES=(research_complete draft_complete destination_updated save_confirmed rendered_readback_verified)
ZONES=(PRIVATE FAMILY_FRIENDS WORK SHARED)

usage() {
  /bin/cat <<'EOF'
Usage: validate-setup.sh [--root PATH] [--account-home PATH] [--smoke] [--require-marker]

Validates owner-only AutoAssist first-use configuration. --smoke creates one
local five-stage objective and performs no external mutation. --account-home
binds the installed runtime doctor's account-scoped checks without replacing HOME.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { /bin/echo "Missing value for --root" >&2; exit 2; }
      AUTOASSIST_ROOT="$2"
      shift 2
      ;;
    --account-home)
      [[ $# -ge 2 ]] || { /bin/echo "Missing value for --account-home" >&2; exit 2; }
      ACCOUNT_HOME="$2"
      shift 2
      ;;
    --smoke)
      RUN_SMOKE=1
      shift
      ;;
    --require-marker)
      REQUIRE_MARKER=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      /bin/echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$AUTOASSIST_ROOT" || -L "$AUTOASSIST_ROOT" ]]; then
  /bin/echo "FAIL  AutoAssist root must be a real directory: $AUTOASSIST_ROOT" >&2
  exit 1
fi
AUTOASSIST_ROOT="${AUTOASSIST_ROOT:A}"
if [[ "$AUTOASSIST_ROOT" == "/" || "$AUTOASSIST_ROOT" == "${HOME:A}" ]]; then
  /bin/echo "FAIL  refusing a broad AutoAssist root: $AUTOASSIST_ROOT" >&2
  exit 1
fi
if [[ -z "$ACCOUNT_HOME" || ! -d "$ACCOUNT_HOME" || -L "$ACCOUNT_HOME" ]]; then
  /bin/echo "FAIL  account home must be a real directory: $ACCOUNT_HOME" >&2
  exit 1
fi
ACCOUNT_HOME="${ACCOUNT_HOME:A}"

cleanup() {
  if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" && "$TEMP_ROOT" == "${TMPDIR:-/tmp}"/autoassist-first-time-validate.* ]]; then
    /bin/rm -rf -- "$TEMP_ROOT"
  fi
}
trap cleanup EXIT INT TERM
TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/autoassist-first-time-validate.XXXXXX")"

pass() {
  /bin/echo "PASS  $1"
}

fail() {
  /bin/echo "FAIL  $1" >&2
  FAILURES=$((FAILURES + 1))
}

check_regular_file() {
  local file="$1"
  local label="$2"
  if [[ -f "$file" && ! -L "$file" ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_mode() {
  local path="$1"
  local expected="$2"
  local label="$3"
  if [[ ! -e "$path" || -L "$path" ]]; then
    fail "$label"
    return
  fi
  local actual
  actual="$(/usr/bin/stat -f '%Lp' "$path")"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (expected $expected, found $actual)"
  fi
}

CONFIG_VALUE=""
read_value() {
  local file="$1"
  local key="$2"
  local count
  count="$(/usr/bin/awk -F= -v key="$key" '$1 == key { count += 1 } END { print count + 0 }' "$file")"
  if [[ "$count" != "1" ]]; then
    fail "$file contains exactly one $key record"
    CONFIG_VALUE=""
    return 1
  fi
  CONFIG_VALUE="$(/usr/bin/awk -v key="$key" 'index($0, key "=") == 1 { sub(/^[^=]*=/, ""); print; exit }' "$file")"
  return 0
}

check_exact_value() {
  local file="$1"
  local key="$2"
  local expected="$3"
  if ! read_value "$file" "$key"; then return; fi
  if [[ "$CONFIG_VALUE" == "$expected" ]]; then
    pass "$key"
  else
    fail "$key must equal $expected"
  fi
}

check_allowed_value() {
  local file="$1"
  local key="$2"
  shift 2
  if ! read_value "$file" "$key"; then return; fi
  local allowed
  for allowed in "$@"; do
    if [[ "$CONFIG_VALUE" == "$allowed" ]]; then
      pass "$key"
      return
    fi
  done
  fail "$key has an unsupported value"
}

check_label() {
  local file="$1"
  local key="$2"
  if ! read_value "$file" "$key"; then return; fi
  if [[ "$CONFIG_VALUE" =~ '^[A-Za-z0-9][A-Za-z0-9 ._@+:/()_-]{0,127}$' ]]; then
    pass "$key non-secret label"
  else
    fail "$key must be a bounded non-secret label"
  fi
}

check_no_secret_material() {
  local file="$1"
  if /usr/bin/grep -Eiq '^[[:space:]]*(PASSWORD|PASSCODE|PASSPHRASE|TOKEN|ACCESS_TOKEN|REFRESH_TOKEN|API_KEY|SECRET|PRIVATE_KEY|RECOVERY_KEY|AUTH_CODE|OTP|MFA_CODE|CVC|CARD_NUMBER)=' "$file" \
    || /usr/bin/grep -Eiq -- '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----' "$file"; then
    fail "no credential-bearing keys or private-key material in ${file:t}"
  else
    pass "no credential-bearing keys or private-key material in ${file:t}"
  fi
}

PROFILE="$AUTOASSIST_ROOT/config/profile.conf"
SETUP="$AUTOASSIST_ROOT/config/first-time.conf"
MARKER="$AUTOASSIST_ROOT/.install-state/first-time-complete"
RUNTIME="$AUTOASSIST_ROOT/runtime/bin/autoassist"

check_regular_file "$AUTOASSIST_ROOT/AGENTS.md" "operating contract present"
check_regular_file "$AUTOASSIST_ROOT/00_CONTEXT/PRIVACY-ZONES.md" "privacy-zone policy present"
check_regular_file "$AUTOASSIST_ROOT/00_CONTEXT/OUTBOUND-ACTION-POLICY.md" "outbound-action policy present"
check_regular_file "$AUTOASSIST_ROOT/skills/first-time/SKILL.md" "first-time skill present"
check_regular_file "$RUNTIME" "AutoAssist runtime present"
check_regular_file "$PROFILE" "profile configuration present"
check_regular_file "$SETUP" "first-time configuration present"

if [[ -f "$PROFILE" && ! -L "$PROFILE" ]]; then
  check_mode "$PROFILE" 600 "profile configuration is owner-only"
  check_no_secret_material "$PROFILE"
  check_label "$PROFILE" AUTOASSIST_USER_LABEL
  if read_value "$PROFILE" AUTOASSIST_HOME; then
    if [[ "$CONFIG_VALUE" == "$AUTOASSIST_ROOT" ]]; then pass "AUTOASSIST_HOME pinned"; else fail "AUTOASSIST_HOME must equal the validated root"; fi
  fi
  check_label "$PROFILE" CHATGPT_ACCOUNT_LABEL
  check_label "$PROFILE" DEFAULT_BROWSER_LABEL
  check_label "$PROFILE" DEFAULT_BROWSER_PROFILE_LABEL
  check_label "$PROFILE" DEFAULT_DESTINATION_LABEL
  check_exact_value "$PROFILE" PRIVACY_MODE separate-zones
  check_exact_value "$PROFILE" TERMINAL_UPDATES chatgpt
fi

ACTIVE_ZONES=""
SHARED_OPT_IN=""
TONE_MODE=""
TONE_PROFILES=""
REQUESTED_CAPABILITIES=""
PERMISSION_MICROPHONE=""
PERMISSION_SCREEN_RECORDING=""
PERMISSION_ACCESSIBILITY=""
PERMISSION_AUTOMATION=""
PERMISSION_FILES_AND_FOLDERS=""
if [[ -f "$SETUP" && ! -L "$SETUP" ]]; then
  check_mode "$SETUP" 600 "first-time configuration is owner-only"
  check_no_secret_material "$SETUP"
  check_exact_value "$SETUP" SETUP_VERSION 1
  check_exact_value "$SETUP" DEDICATED_LAPTOP_READY yes
  check_allowed_value "$SETUP" CHATGPT_SIGN_IN_METHOD already-signed-in native-sso os-sso browser-sso
  check_exact_value "$SETUP" CHATGPT_SIGN_IN_CONFIRMED yes
  if read_value "$SETUP" REQUESTED_CAPABILITIES; then REQUESTED_CAPABILITIES="$CONFIG_VALUE"; fi
  check_allowed_value "$SETUP" PERMISSION_MICROPHONE confirmed-by-user deferred-not-needed required-later
  if read_value "$SETUP" PERMISSION_MICROPHONE; then PERMISSION_MICROPHONE="$CONFIG_VALUE"; fi
  check_allowed_value "$SETUP" PERMISSION_SCREEN_RECORDING confirmed-by-user deferred-not-needed required-later
  if read_value "$SETUP" PERMISSION_SCREEN_RECORDING; then PERMISSION_SCREEN_RECORDING="$CONFIG_VALUE"; fi
  check_allowed_value "$SETUP" PERMISSION_ACCESSIBILITY confirmed-by-user deferred-not-needed required-later
  if read_value "$SETUP" PERMISSION_ACCESSIBILITY; then PERMISSION_ACCESSIBILITY="$CONFIG_VALUE"; fi
  check_allowed_value "$SETUP" PERMISSION_AUTOMATION confirmed-by-user deferred-not-needed required-later
  if read_value "$SETUP" PERMISSION_AUTOMATION; then PERMISSION_AUTOMATION="$CONFIG_VALUE"; fi
  check_allowed_value "$SETUP" PERMISSION_FILES_AND_FOLDERS confirmed-by-user deferred-not-needed required-later
  if read_value "$SETUP" PERMISSION_FILES_AND_FOLDERS; then PERMISSION_FILES_AND_FOLDERS="$CONFIG_VALUE"; fi
  if read_value "$SETUP" ACTIVE_PRIVACY_ZONES; then ACTIVE_ZONES="$CONFIG_VALUE"; fi
  if read_value "$SETUP" SHARED_ZONE_OPT_IN; then SHARED_OPT_IN="$CONFIG_VALUE"; fi
  if read_value "$SETUP" TONE_LEARNING; then TONE_MODE="$CONFIG_VALUE"; fi
  if read_value "$SETUP" TONE_PROFILE_IDS; then TONE_PROFILES="$CONFIG_VALUE"; fi
  check_exact_value "$SETUP" RAW_MESSAGE_RETENTION disabled
  check_exact_value "$SETUP" CONNECTOR_WRITE_MODE read-only
  check_exact_value "$SETUP" EXTERNAL_WRITE_POLICY first-party-rendered-only
  check_exact_value "$SETUP" NO_ATTRIBUTION_POLICY fail-closed
  check_exact_value "$SETUP" NATIVE_GOAL_PERSISTENCE required
fi

typeset -A seen_capabilities
if [[ -z "$REQUESTED_CAPABILITIES" ]]; then
  pass "no optional capabilities requested"
else
  capability_values=("${(@s:,:)REQUESTED_CAPABILITIES}")
  capabilities_valid=1
  for capability in "${capability_values[@]}"; do
    if [[ "$capability" != "voice" && "$capability" != "computer-use" && "$capability" != "app-automation" && "$capability" != "protected-local-files" && "$capability" != "native-goal" ]]; then
      capabilities_valid=0
    fi
    if [[ -n "${seen_capabilities[$capability]:-}" ]]; then capabilities_valid=0; fi
    seen_capabilities[$capability]=1
  done
  if [[ "$capabilities_valid" -eq 1 ]]; then pass "requested capability labels"; else fail "requested capability labels"; fi
fi

if [[ -n "${seen_capabilities[voice]:-}" ]]; then
  if [[ "$PERMISSION_MICROPHONE" == "confirmed-by-user" ]]; then pass "voice requires microphone confirmed-by-user"; else fail "voice requires microphone confirmed-by-user"; fi
fi
if [[ -n "${seen_capabilities[computer-use]:-}" ]]; then
  if [[ "$PERMISSION_SCREEN_RECORDING" == "confirmed-by-user" ]]; then pass "computer-use requires screen recording confirmed-by-user"; else fail "computer-use requires screen recording confirmed-by-user"; fi
  if [[ "$PERMISSION_ACCESSIBILITY" == "confirmed-by-user" ]]; then pass "computer-use requires accessibility confirmed-by-user"; else fail "computer-use requires accessibility confirmed-by-user"; fi
fi
if [[ -n "${seen_capabilities[app-automation]:-}" ]]; then
  if [[ "$PERMISSION_AUTOMATION" == "confirmed-by-user" ]]; then pass "app-automation requires automation confirmed-by-user"; else fail "app-automation requires automation confirmed-by-user"; fi
fi
if [[ -n "${seen_capabilities[protected-local-files]:-}" ]]; then
  if [[ "$PERMISSION_FILES_AND_FOLDERS" == "confirmed-by-user" ]]; then pass "protected-local-files requires files and folders confirmed-by-user"; else fail "protected-local-files requires files and folders confirmed-by-user"; fi
fi
if [[ -n "${seen_capabilities[native-goal]:-}" ]]; then
  if [[ -f "$SETUP" && ! -L "$SETUP" ]] && read_value "$SETUP" NATIVE_GOAL_PERSISTENCE && [[ "$CONFIG_VALUE" == "required" ]]; then
    pass "native-goal requires native Goal persistence"
  else
    fail "native-goal requires native Goal persistence"
  fi
fi

for zone in "${ZONES[@]}"; do
  zone_path="$AUTOASSIST_ROOT/00_CONTEXT/$zone"
  if [[ -d "$zone_path" && ! -L "$zone_path" ]]; then
    pass "$zone zone present"
    check_mode "$zone_path" 700 "$zone zone is owner-only"
    check_regular_file "$zone_path/INDEX.md" "$zone index present"
    if [[ -f "$zone_path/INDEX.md" && ! -L "$zone_path/INDEX.md" ]]; then
      check_mode "$zone_path/INDEX.md" 600 "$zone index is owner-only"
    fi
  else
    fail "$zone zone present"
  fi
done

typeset -A seen_zones
if [[ -n "$ACTIVE_ZONES" ]]; then
  active_values=("${(@s:,:)ACTIVE_ZONES}")
  active_valid=1
  for zone in "${active_values[@]}"; do
    if [[ "$zone" != "PRIVATE" && "$zone" != "FAMILY_FRIENDS" && "$zone" != "WORK" && "$zone" != "SHARED" ]]; then active_valid=0; fi
    if [[ -n "${seen_zones[$zone]:-}" ]]; then active_valid=0; fi
    seen_zones[$zone]=1
  done
  if [[ "$active_valid" -eq 1 ]]; then pass "active privacy-zone labels"; else fail "active privacy-zone labels"; fi
  if [[ -n "${seen_zones[SHARED]:-}" && "$SHARED_OPT_IN" != "yes" ]]; then
    fail "SHARED requires explicit opt-in"
  elif [[ -z "${seen_zones[SHARED]:-}" && "$SHARED_OPT_IN" != "no" ]]; then
    fail "SHARED opt-in must be no when SHARED is inactive"
  else
    pass "SHARED opt-in consistency"
  fi
else
  fail "at least one active privacy zone is required"
fi

declared_tone_artifacts=()
if [[ "$TONE_MODE" == "disabled" ]]; then
  if [[ -z "$TONE_PROFILES" ]]; then pass "tone learning disabled without profiles"; else fail "disabled tone learning cannot name profiles"; fi
elif [[ "$TONE_MODE" == "opt-in" ]]; then
  if [[ -z "$TONE_PROFILES" ]]; then
    fail "opt-in tone learning requires at least one profile"
  else
    tone_values=("${(@s:,:)TONE_PROFILES}")
    typeset -A seen_profiles
    tone_valid=1
    for profile in "${tone_values[@]}"; do
      if [[ ! "$profile" =~ '^[a-z0-9][a-z0-9-]{2,63}$' || -n "${seen_profiles[$profile]:-}" ]]; then
        tone_valid=0
        fail "opted-in tone profile IDs are unique"
      fi
      seen_profiles[$profile]=1

      expected_channel=""
      expected_audience=""
      expected_zone=""
      case "$profile" in
        email-work-external)
          expected_channel="email"; expected_audience="work-external"; expected_zone="WORK"
          ;;
        email-work-internal)
          expected_channel="email"; expected_audience="work-internal"; expected_zone="WORK"
          ;;
        chat-work-internal)
          expected_channel="chat"; expected_audience="work-internal"; expected_zone="WORK"
          ;;
        text-family-friends)
          expected_channel="text"; expected_audience="family-friends"; expected_zone="FAMILY_FRIENDS"
          ;;
        social-public)
          expected_channel="social"; expected_audience="public"; expected_zone="SHARED"
          ;;
        *)
          tone_valid=0
          fail "approved tone profile ID: $profile"
          continue
          ;;
      esac

      if [[ -n "${seen_zones[$expected_zone]:-}" ]]; then pass "$profile mapped privacy zone is active"; else fail "$profile mapped privacy zone is active"; fi
      if [[ "$expected_zone" == "SHARED" && "$SHARED_OPT_IN" != "yes" ]]; then
        fail "$profile requires explicit SHARED opt-in"
      fi

      profile_dir="$AUTOASSIST_ROOT/00_CONTEXT/$expected_zone/COMMUNICATION-PROFILES"
      profile_artifact="$profile_dir/$profile.md"
      declared_tone_artifacts+=("$profile_artifact")
      if [[ -d "$profile_dir" && ! -L "$profile_dir" ]]; then
        pass "$profile tone profile directory present"
        check_mode "$profile_dir" 700 "$profile tone profile directory is owner-only"
      else
        fail "$profile tone profile directory present"
      fi
      check_regular_file "$profile_artifact" "$profile tone profile artifact present"
      if [[ -f "$profile_artifact" && ! -L "$profile_artifact" ]]; then
        check_mode "$profile_artifact" 600 "$profile tone profile artifact is owner-only"
        check_no_secret_material "$profile_artifact"
        check_exact_value "$profile_artifact" PROFILE_ID "$profile"
        check_exact_value "$profile_artifact" CHANNEL "$expected_channel"
        check_exact_value "$profile_artifact" AUDIENCE "$expected_audience"
        check_exact_value "$profile_artifact" ZONE "$expected_zone"
        check_exact_value "$profile_artifact" LEARNING_MODE aggregate-only
        check_exact_value "$profile_artifact" RAW_MESSAGE_RETENTION disabled
        check_exact_value "$profile_artifact" SOURCE_EXAMPLES_RETAINED no
        profile_patterns_status=""
        if read_value "$profile_artifact" PATTERNS_STATUS; then profile_patterns_status="$CONFIG_VALUE"; fi
        profile_line_count="$(/usr/bin/awk 'END { print NR + 0 }' "$profile_artifact")"
        if [[ "$profile_patterns_status" == "empty-awaiting-user-approved-examples" ]]; then
          if [[ "$profile_line_count" == "8" ]]; then pass "$profile initialized schema is exact"; else fail "$profile initialized schema is exact"; fi
        elif [[ "$profile_patterns_status" == "learned-aggregate" ]]; then
          if read_value "$profile_artifact" AGGREGATE_SAMPLE_COUNT; then
            if [[ "$CONFIG_VALUE" =~ '^[1-9][0-9]{0,5}$' ]]; then pass "$profile aggregate sample count is bounded"; else fail "$profile aggregate sample count is bounded"; fi
          fi
          check_allowed_value "$profile_artifact" FORMALITY casual balanced formal
          check_allowed_value "$profile_artifact" DIRECTNESS direct balanced gentle
          check_allowed_value "$profile_artifact" WARMTH reserved balanced warm
          check_allowed_value "$profile_artifact" BREVITY brief balanced detailed
          check_allowed_value "$profile_artifact" EMOJI_FREQUENCY none rare sometimes frequent
          check_allowed_value "$profile_artifact" GREETING_STYLE none brief personal
          check_allowed_value "$profile_artifact" CLOSING_STYLE none brief personal
          if [[ "$profile_line_count" == "16" ]]; then pass "$profile learned aggregate schema is exact and bounded"; else fail "$profile learned aggregate schema is exact and bounded"; fi
        else
          fail "$profile PATTERNS_STATUS must describe an initialized or learned aggregate"
        fi
        if /usr/bin/grep -Eiq '^[[:space:]]*(RAW_MESSAGE|MESSAGE|MESSAGE_BODY|SOURCE_TEXT|QUOTE|QUOTED_TEXT|EXAMPLE|SOURCE_EXAMPLE|SOURCE_MESSAGE)=' "$profile_artifact"; then
          fail "$profile contains no raw messages or source examples"
        else
          pass "$profile contains no raw messages or source examples"
        fi
      fi

      profile_id_count=0
      for candidate in "$AUTOASSIST_ROOT"/00_CONTEXT/*/COMMUNICATION-PROFILES/*.md(N); do
        if [[ -f "$candidate" && ! -L "$candidate" ]]; then
          candidate_count="$(/usr/bin/awk -F= -v id="$profile" '$1 == "PROFILE_ID" && $2 == id { count += 1 } END { print count + 0 }' "$candidate")"
          profile_id_count=$((profile_id_count + candidate_count))
        fi
      done
      if [[ "$profile_id_count" -eq 1 ]]; then pass "$profile PROFILE_ID is globally unique"; else fail "$profile PROFILE_ID is globally unique"; fi
    done
    if [[ "$tone_valid" -eq 1 ]]; then pass "opt-in tone profile labels"; else fail "opt-in tone profile labels"; fi
  fi
else
  fail "TONE_LEARNING must be disabled or opt-in"
fi

# The materialized profile set must exactly equal the declared profile set.
# Enumerate only the four canonical roots and never follow symlinks or recurse.
for zone in "${ZONES[@]}"; do
  profile_root="$AUTOASSIST_ROOT/00_CONTEXT/$zone/COMMUNICATION-PROFILES"
  if [[ -L "$profile_root" || ( -e "$profile_root" && ! -d "$profile_root" ) ]]; then
    fail "$zone communication-profile root is a real directory when present"
    continue
  fi
  if [[ ! -d "$profile_root" ]]; then
    continue
  fi
  check_mode "$profile_root" 700 "$zone communication-profile root is owner-only"
  for profile_entry in "$profile_root"/*(DN); do
    declared_entry=0
    for declared_artifact in "${declared_tone_artifacts[@]}"; do
      if [[ "$profile_entry" == "$declared_artifact" ]]; then
        declared_entry=1
        break
      fi
    done
    if [[ "$declared_entry" -eq 1 && -f "$profile_entry" && ! -L "$profile_entry" ]]; then
      pass "${profile_entry:t} is a declared tone artifact"
    else
      fail "undeclared communication-profile artifact rejected: ${profile_entry:t}"
    fi
  done
done

DOCTOR_LOG="$TEMP_ROOT/doctor.log"
if [[ -x "$RUNTIME" ]]; then
  if AUTOASSIST_ACCOUNT_HOME="$ACCOUNT_HOME" "$RUNTIME" doctor --quiet >"$DOCTOR_LOG" 2>&1; then
    pass "AutoAssist doctor for explicit account home"
  else
    fail "AutoAssist doctor for explicit account home"
    /bin/cat "$DOCTOR_LOG" >&2
  fi
else
  fail "AutoAssist runtime is executable"
fi

validate_smoke_objective() {
  local objective_id="$1"
  local evidence_dir="$AUTOASSIST_ROOT/03_OUTPUTS/.first-time-smoke/$objective_id"
  local status_json="$TEMP_ROOT/objective-status-$objective_id.json"
  if [[ ! "$objective_id" =~ '^[a-z0-9][a-z0-9-]{2,63}$' || ! -d "$evidence_dir" || -L "$evidence_dir" ]]; then
    fail "smoke objective exists"
    return
  fi
  if ! "$RUNTIME" objective-status "$objective_id" > "$status_json" 2>/dev/null; then
    fail "smoke objective status is readable"
    return
  fi
  readiness="$(/usr/bin/plutil -extract result.readiness.complete raw -o - "$status_json" 2>/dev/null || true)"
  if [[ "$readiness" == "true" ]]; then pass "smoke objective complete"; else fail "smoke objective complete"; fi
  local stage
  for stage in "${STAGES[@]}"; do
    if [[ "$readiness" == "true" ]]; then
      pass "smoke $stage validated"
      pass "smoke $stage distinct producer/validator labels"
    else
      fail "smoke $stage validated"
      fail "smoke $stage distinct producer/validator labels"
    fi
    evidence="$evidence_dir/$stage.txt"
    if [[ -f "$evidence" && ! -L "$evidence" ]] && /usr/bin/grep -qx 'external_mutation=false' "$evidence"; then
      pass "smoke $stage no external mutation"
    else
      fail "smoke $stage no external mutation"
    fi
  done
}

run_smoke() {
  if [[ "$FAILURES" -ne 0 ]]; then
    fail "smoke skipped because setup validation failed"
    return
  fi
  SMOKE_OBJECTIVE_ID="first-time-smoke-$(/bin/date -u +%Y%m%d%H%M%S)-$$"
  if ! "$RUNTIME" objective-create "$SMOKE_OBJECTIVE_ID" "First-time local no-external-mutation smoke" >"$TEMP_ROOT/objective-create.log" 2>&1; then
    fail "create local smoke objective"
    /bin/cat "$TEMP_ROOT/objective-create.log" >&2
    return
  fi
  pass "create local smoke objective"
  evidence_dir="$AUTOASSIST_ROOT/03_OUTPUTS/.first-time-smoke/$SMOKE_OBJECTIVE_ID"
  /bin/mkdir -p "$evidence_dir"
  /bin/chmod 700 "$AUTOASSIST_ROOT/03_OUTPUTS/.first-time-smoke" "$evidence_dir"
  local stage
  for stage in "${STAGES[@]}"; do
    evidence="$evidence_dir/$stage.txt"
    /usr/bin/printf '%s\n' \
      "objective_id=$SMOKE_OBJECTIVE_ID" \
      "stage=$stage" \
      "external_mutation=false" \
      "check=local-first-time-smoke" \
      "captured_at=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" > "$evidence"
    /bin/chmod 600 "$evidence"
    if ! "$RUNTIME" checkpoint "$SMOKE_OBJECTIVE_ID" "$stage" "$evidence" first-time-smoke-producer >"$TEMP_ROOT/checkpoint-$stage.log" 2>&1; then
      fail "report smoke $stage"
      /bin/cat "$TEMP_ROOT/checkpoint-$stage.log" >&2
      return
    fi
    if ! "$RUNTIME" validate-stage "$SMOKE_OBJECTIVE_ID" "$stage" first-time-smoke-validator >"$TEMP_ROOT/validate-$stage.log" 2>&1; then
      fail "validate smoke $stage"
      /bin/cat "$TEMP_ROOT/validate-$stage.log" >&2
      return
    fi
  done
  validate_smoke_objective "$SMOKE_OBJECTIVE_ID"
}

validate_marker() {
  if [[ ! -f "$MARKER" || -L "$MARKER" ]]; then
    fail "first-time completion marker present"
    return
  fi
  check_mode "$MARKER" 600 "first-time completion marker is owner-only"
  check_no_secret_material "$MARKER"
  check_exact_value "$MARKER" SETUP_VERSION 1
  if read_value "$MARKER" COMPLETED_AT; then
    if [[ "$CONFIG_VALUE" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' ]]; then pass "completion timestamp"; else fail "completion timestamp"; fi
  fi
  check_label "$MARKER" VALIDATOR_LABEL
  if read_value "$MARKER" SETUP_CONFIG_SHA256; then
    expected_setup_hash="$(/usr/bin/shasum -a 256 "$SETUP" | /usr/bin/awk '{print $1}')"
    if [[ "$CONFIG_VALUE" == "$expected_setup_hash" ]]; then pass "completion marker setup hash"; else fail "completion marker setup hash"; fi
  fi
  if read_value "$MARKER" SMOKE_OBJECTIVE_ID; then
    SMOKE_OBJECTIVE_ID="$CONFIG_VALUE"
    validate_smoke_objective "$SMOKE_OBJECTIVE_ID"
  fi
}

if [[ "$RUN_SMOKE" -eq 1 ]]; then run_smoke; fi
if [[ "$REQUIRE_MARKER" -eq 1 || -f "$MARKER" ]]; then validate_marker; fi

if [[ "$FAILURES" -ne 0 ]]; then
  /bin/echo "AutoAssist first-time setup validation failed with $FAILURES check(s)." >&2
  exit 1
fi

/bin/echo "AutoAssist first-time setup validation passed."
if [[ -n "$SMOKE_OBJECTIVE_ID" ]]; then /bin/echo "SMOKE_OBJECTIVE_ID=$SMOKE_OBJECTIVE_ID"; fi
/bin/echo "EXTERNAL_MUTATION=false"
