#!/bin/zsh

set -eu
umask 077

ROOT=""
ACCOUNT_HOME=""
ACTION=""
STAGE=""
STATUS=""
GATE="none"
EVIDENCE="none"
SMOKE_OBJECTIVE_ID="none"

usage() {
  /bin/cat <<'EOF'
Usage: walkthrough-progress.sh --root ROOT --account-home HOME show
       walkthrough-progress.sh --root ROOT --account-home HOME record \
         --stage STAGE --status STATUS --gate GATE --evidence EVIDENCE \
         [--smoke-objective ID]

record accepts only these exact values:
  STAGE:    installed | project-primary | local-configuration | native-capabilities | local-smoke | independent-review | complete
  STATUS:   active | waiting-user | pending-capability | ready-for-review | complete
  GATE:     none | sign-in | project-primary | computer-use-install | target-app-approval | microphone | screen-recording | accessibility | automation | protected-files | security-consent | node-unavailable
  EVIDENCE: none | installed-receipt | primary-project-readback | local-config-readback | native-capability-readback | fresh-readable-gate | fresh-post-gate-readback | capability-unavailable | doctor-readback | local-smoke-readback | independent-acceptance | marker-readback

Examples:
  walkthrough-progress.sh --root ROOT --account-home HOME show
  walkthrough-progress.sh --root ROOT --account-home HOME record \
    --stage local-smoke --status active --gate none --evidence doctor-readback
  walkthrough-progress.sh --root ROOT --account-home HOME record \
    --stage independent-review --status ready-for-review --gate none \
    --evidence local-smoke-readback --smoke-objective SMOKE_ID

The checkpoint is resume metadata only. It cannot create or replace the
first-time completion marker. Read references/setup-workflow.md before writing
the marker and use its exact schema and readback sequence. A
ready-for-review cursor is accepted only while objective-status is complete
and all five smoke evidence files still bind their objective and stage with
external_mutation=false; show rejects stale or missing smoke evidence.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --account-home) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; ACCOUNT_HOME="$2"; shift 2 ;;
    show|record) [[ -z "$ACTION" ]] || { usage >&2; exit 2; }; ACTION="$1"; shift ;;
    --stage) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; STAGE="$2"; shift 2 ;;
    --status) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; STATUS="$2"; shift 2 ;;
    --gate) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; GATE="$2"; shift 2 ;;
    --evidence) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; EVIDENCE="$2"; shift 2 ;;
    --smoke-objective) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; SMOKE_OBJECTIVE_ID="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[[ -n "$ROOT" && -n "$ACCOUNT_HOME" && -n "$ACTION" ]] || { usage >&2; exit 2; }
[[ "$ROOT" == /* && "$ACCOUNT_HOME" == /* && "$ROOT" == "$ACCOUNT_HOME"/* ]] || { /bin/echo "Walkthrough paths must be absolute and installation-scoped." >&2; exit 1; }
walkthrough_die() {
  /bin/echo "AutoAssist: $*" >&2
  exit 1
}
safe_absolute_path() {
  local path="$1"
  [[ -n "$path" && "$path" == /* && "$path" != / && "$path" != *$'\n'* \
    && "$path" != *'//'* && "$path" != *'/../'* && "$path" != */.. \
    && "$path" != *'/./'* && "$path" != */. \
    && "$path" =~ '^[A-Za-z0-9._/ -]+$' ]]
}
reject_raw_symlink_components() {
  local path="$1"
  local cursor="/"
  local component
  local -a components
  components=("${(@s:/:)${path#/}}")
  for component in "${components[@]}"; do
    [[ -z "$component" ]] && continue
    if [[ "$cursor" == / ]]; then cursor="/$component"; else cursor="$cursor/$component"; fi
    [[ -L "$cursor" ]] && { /bin/echo "Walkthrough path contains a symlink component: $cursor" >&2; exit 1; }
  done
}
reject_raw_symlink_components "$ACCOUNT_HOME"
reject_raw_symlink_components "$ROOT"
safe_absolute_path "$ACCOUNT_HOME" && safe_absolute_path "$ROOT" || walkthrough_die "walkthrough paths are unsafe"
[[ -d "$ROOT" && ! -L "$ROOT" && -d "$ACCOUNT_HOME" && ! -L "$ACCOUNT_HOME" ]] || { /bin/echo "Walkthrough paths must be real directories." >&2; exit 1; }
ROOT="${ROOT:A}"
ACCOUNT_HOME="${ACCOUNT_HOME:A}"
[[ "$ROOT" == "$ACCOUNT_HOME"/* ]] || { /bin/echo "Walkthrough root escaped the selected account home." >&2; exit 1; }
SCRIPT_ROOT="${0:A:h:h:h:h}"
[[ "$SCRIPT_ROOT" == "$ROOT" ]] || walkthrough_die "walkthrough helper does not belong to the selected installation"
STATE_DIR="$ROOT/.install-state"
[[ -d "$STATE_DIR" && ! -L "$STATE_DIR" \
  && "$(/usr/bin/stat -f '%u' "$STATE_DIR")" == "$(/usr/bin/id -u)" \
  && "$(/usr/bin/stat -f '%Lp' "$STATE_DIR")" == 700 ]] || walkthrough_die "walkthrough state directory is unsafe"
MANAGED_MARKER="$ROOT/.install-state/managed-by-autoassist"
[[ -f "$MANAGED_MARKER" && ! -L "$MANAGED_MARKER" \
  && "$(/usr/bin/stat -f '%u' "$MANAGED_MARKER")" == "$(/usr/bin/id -u)" \
  && "$(/usr/bin/stat -f '%Lp' "$MANAGED_MARKER")" == 600 \
  && "$(/usr/bin/stat -f '%l' "$MANAGED_MARKER")" == 1 ]] || walkthrough_die "walkthrough requires a safe managed installation marker"
/usr/bin/grep -F -x -q 'managed-by=AutoAssist' "$MANAGED_MARKER" || walkthrough_die "walkthrough installation ownership mismatch"

RECEIPT="$ROOT/.install-state/receipt.json"
[[ -f "$RECEIPT" && ! -L "$RECEIPT" \
  && "$(/usr/bin/stat -f '%u' "$RECEIPT")" == "$(/usr/bin/id -u)" \
  && "$(/usr/bin/stat -f '%Lp' "$RECEIPT")" == 600 \
  && "$(/usr/bin/stat -f '%l' "$RECEIPT")" == 1 \
  && "$(/usr/bin/stat -f '%z' "$RECEIPT")" -le 16384 ]] || walkthrough_die "walkthrough requires a safe installation receipt"
receipt_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$RECEIPT" 2>/dev/null || walkthrough_die "walkthrough receipt is invalid"
}
[[ "$(receipt_value product_id)" == Autobot \
  && "$(receipt_value root)" == "$ROOT" \
  && "$(receipt_value account_home)" == "$ACCOUNT_HOME" \
  && "$(receipt_value owner_uid)" == "$(/usr/bin/id -u)" ]] || walkthrough_die "walkthrough receipt binding mismatch"

COMMON="$SCRIPT_ROOT/runtime/lib/install-common.sh"
[[ -f "$COMMON" && ! -L "$COMMON" \
  && "$(/usr/bin/stat -f '%u' "$COMMON")" == "$(/usr/bin/id -u)" \
  && "$(/usr/bin/stat -f '%l' "$COMMON")" == 1 ]] || walkthrough_die "installed lifecycle helpers are unavailable"
source "$COMMON"
aa_safe_absolute_path "$ROOT" && aa_safe_absolute_path "$ACCOUNT_HOME" || aa_die "walkthrough paths are unsafe"
aa_require_child "$ROOT" "$ACCOUNT_HOME"
aa_reject_symlink_components "$ROOT"

STATE="$ROOT/.install-state/first-time-progress"
ROOT_SHA256="$(/usr/bin/printf '%s' "$ROOT" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"

aa_check_owned_ancestors "$STATE_DIR" "$ROOT"
[[ -d "$STATE_DIR" && ! -L "$STATE_DIR" && "$(/usr/bin/stat -f '%u' "$STATE_DIR")" == "$(/usr/bin/id -u)" \
  && "$(/usr/bin/stat -f '%Lp' "$STATE_DIR")" == 700 ]] || aa_die "walkthrough state directory is unsafe"

valid_stage() {
  case "$1" in installed|project-primary|local-configuration|native-capabilities|local-smoke|independent-review|complete) return 0;; *) return 1;; esac
}
valid_status() {
  case "$1" in active|waiting-user|pending-capability|ready-for-review|complete) return 0;; *) return 1;; esac
}
valid_gate() {
  case "$1" in none|sign-in|project-primary|computer-use-install|target-app-approval|microphone|screen-recording|accessibility|automation|protected-files|security-consent|node-unavailable) return 0;; *) return 1;; esac
}
valid_evidence() {
  case "$1" in none|installed-receipt|primary-project-readback|local-config-readback|native-capability-readback|fresh-readable-gate|fresh-post-gate-readback|capability-unavailable|doctor-readback|local-smoke-readback|independent-acceptance|marker-readback) return 0;; *) return 1;; esac
}
stage_rank() {
  case "$1" in installed) print 1;; project-primary) print 2;; local-configuration) print 3;; native-capabilities) print 4;; local-smoke) print 5;; independent-review) print 6;; complete) print 7;; esac
}

smoke_objective_readback_valid() {
  local objective_id="$1"
  local evidence_dir="$ROOT/03_OUTPUTS/.first-time-smoke/$objective_id"
  local status_file=""
  local stage
  local evidence
  local readiness
  local -a smoke_stages
  smoke_stages=(research_complete draft_complete destination_updated save_confirmed rendered_readback_verified)

  [[ "$objective_id" =~ '^[a-z0-9][a-z0-9-]{2,63}$' ]] || return 1
  [[ -d "$evidence_dir" && ! -L "$evidence_dir" \
    && "$(/usr/bin/stat -f '%u' "$evidence_dir")" == "$(/usr/bin/id -u)" \
    && "$(/usr/bin/stat -f '%Lp' "$evidence_dir")" == 700 ]] || return 1
  RUNTIME="$ROOT/runtime/bin/autoassist"
  [[ -f "$RUNTIME" && ! -L "$RUNTIME" && -x "$RUNTIME" ]] || return 1
  status_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/autoassist-first-time-progress.XXXXXX")" || return 1
  if ! "$RUNTIME" objective-status "$objective_id" > "$status_file" 2>/dev/null; then
    /bin/rm -f -- "$status_file"
    return 1
  fi
  readiness="$(/usr/bin/plutil -extract result.readiness.complete raw -o - "$status_file" 2>/dev/null || true)"
  if [[ "$readiness" != true ]]; then
    /bin/rm -f -- "$status_file"
    return 1
  fi
  for stage in "${smoke_stages[@]}"; do
    evidence="$evidence_dir/$stage.txt"
    if [[ ! -f "$evidence" || -L "$evidence" \
      || "$(/usr/bin/stat -f '%u' "$evidence")" != "$(/usr/bin/id -u)" \
      || "$(/usr/bin/stat -f '%Lp' "$evidence")" != 600 ]]; then
      /bin/rm -f -- "$status_file"
      return 1
    fi
    if ! /usr/bin/grep -F -x -q "objective_id=$objective_id" "$evidence" \
      || ! /usr/bin/grep -F -x -q "stage=$stage" "$evidence" \
      || ! /usr/bin/grep -F -x -q 'external_mutation=false' "$evidence"; then
      /bin/rm -f -- "$status_file"
      return 1
    fi
  done
  /bin/rm -f -- "$status_file"
  return 0
}

read_record() {
  local key="$1"
  [[ -f "$STATE" && ! -L "$STATE" ]] || return 1
  local count
  count="$(/usr/bin/awk -F= -v key="$key" '$1 == key { count++ } END { print count + 0 }' "$STATE")"
  [[ "$count" == 1 ]] || return 1
  /usr/bin/awk -v key="$key" 'index($0, key "=") == 1 { sub(/^[^=]*=/, ""); print; exit }' "$STATE"
}

load_and_validate_record() {
  [[ -f "$STATE" && ! -L "$STATE" \
    && "$(/usr/bin/stat -f '%u' "$STATE")" == "$(/usr/bin/id -u)" \
    && "$(/usr/bin/stat -f '%Lp' "$STATE")" == 600 ]] || aa_die "walkthrough progress file is unsafe"
  [[ "$(/usr/bin/awk 'END { print NR + 0 }' "$STATE")" == 9 ]] || aa_die "walkthrough progress schema is invalid"
  [[ "$(read_record WALKTHROUGH_VERSION)" == 1 && "$(read_record ROOT_SHA256)" == "$ROOT_SHA256" ]] || aa_die "walkthrough progress binding mismatch"
  saved_stage="$(read_record STAGE)"
  saved_status="$(read_record STATUS)"
  saved_gate="$(read_record WAITING_GATE)"
  saved_evidence="$(read_record EVIDENCE)"
  saved_smoke="$(read_record SMOKE_OBJECTIVE_ID)"
  saved_config_hash="$(read_record SETUP_CONFIG_SHA256)"
  saved_updated="$(read_record UPDATED_AT)"
  valid_stage "$saved_stage" && valid_status "$saved_status" && valid_gate "$saved_gate" && valid_evidence "$saved_evidence" \
    || aa_die "walkthrough progress contains an unsupported state"
  [[ "$saved_smoke" == none || "$saved_smoke" =~ '^[a-z0-9][a-z0-9-]{2,63}$' ]] || aa_die "walkthrough progress smoke binding is invalid"
  [[ "$saved_config_hash" == none || "$saved_config_hash" =~ '^[0-9a-f]{64}$' ]] || aa_die "walkthrough progress configuration binding is invalid"
  [[ "$saved_updated" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' ]] || aa_die "walkthrough progress timestamp is invalid"
  if [[ "$saved_status" == waiting-user ]]; then
    [[ "$saved_gate" != none && "$saved_evidence" == fresh-readable-gate ]] || aa_die "walkthrough progress user gate is invalid"
  elif [[ "$saved_status" == pending-capability ]]; then
    [[ "$saved_gate" != none && "$saved_evidence" == capability-unavailable ]] || aa_die "walkthrough pending capability is invalid"
  elif [[ "$saved_gate" != none ]]; then
    aa_die "walkthrough progress gate is inconsistent"
  fi
  if [[ "$saved_status" == ready-for-review ]]; then
    [[ "$saved_stage" == independent-review && "$saved_evidence" == local-smoke-readback && "$saved_smoke" != none ]] || aa_die "walkthrough review readiness is invalid"
    smoke_objective_readback_valid "$saved_smoke" || aa_die "walkthrough review smoke evidence is stale"
  fi
}

if [[ "$ACTION" == show ]]; then
  [[ -z "$STAGE" && -z "$STATUS" && "$GATE" == none && "$EVIDENCE" == none && "$SMOKE_OBJECTIVE_ID" == none ]] || { usage >&2; exit 2; }
  if [[ ! -e "$STATE" && ! -L "$STATE" ]]; then
    /usr/bin/printf '{"schema":1,"status":"not-started","stage":"installed","waiting_gate":"none","evidence":"none","smoke_objective_id":"none"}\n'
    exit 0
  fi
  load_and_validate_record
  if [[ "$saved_config_hash" != none ]]; then
    [[ -f "$ROOT/config/first-time.conf" && ! -L "$ROOT/config/first-time.conf" \
      && "$(aa_sha256 "$ROOT/config/first-time.conf")" == "$saved_config_hash" ]] || aa_die "walkthrough progress configuration binding is stale"
  fi
  if [[ "$saved_status" == complete ]]; then
    "$ROOT/skills/first-time/scripts/validate-setup.sh" --root "$ROOT" --account-home "$ACCOUNT_HOME" --require-marker >/dev/null \
      || aa_die "walkthrough completion evidence is stale"
  fi
  /usr/bin/printf '{"schema":1,"status":"%s","stage":"%s","waiting_gate":"%s","evidence":"%s","smoke_objective_id":"%s","setup_config_sha256":"%s","updated_at":"%s"}\n' \
    "$saved_status" "$saved_stage" "$saved_gate" "$saved_evidence" "$saved_smoke" "$saved_config_hash" "$saved_updated"
  exit 0
fi

valid_stage "$STAGE" || aa_usage_die "unsupported walkthrough stage"
valid_status "$STATUS" || aa_usage_die "unsupported walkthrough status"
valid_gate "$GATE" || aa_usage_die "unsupported walkthrough gate"
valid_evidence "$EVIDENCE" || aa_usage_die "unsupported walkthrough evidence"
[[ "$SMOKE_OBJECTIVE_ID" == none || "$SMOKE_OBJECTIVE_ID" =~ '^[a-z0-9][a-z0-9-]{2,63}$' ]] || aa_usage_die "invalid smoke objective id"
if [[ "$STATUS" == waiting-user ]]; then
  [[ "$GATE" != none && "$EVIDENCE" == fresh-readable-gate ]] || aa_usage_die "a user wait requires a typed gate and fresh readable evidence"
elif [[ "$STATUS" == pending-capability ]]; then
  [[ "$GATE" != none && "$EVIDENCE" == capability-unavailable ]] || aa_usage_die "a pending capability requires a typed unavailable capability"
else
  [[ "$GATE" == none ]] || aa_usage_die "only a pending capability may retain a non-user gate"
fi
if [[ "$STATUS" == ready-for-review ]]; then
  [[ "$STAGE" == independent-review && "$EVIDENCE" == local-smoke-readback && "$SMOKE_OBJECTIVE_ID" != none ]] || aa_usage_die "review readiness requires the validated local smoke"
  [[ -f "$ROOT/config/first-time.conf" && ! -L "$ROOT/config/first-time.conf" ]] || aa_die "review readiness requires current setup configuration"
  smoke_objective_readback_valid "$SMOKE_OBJECTIVE_ID" || aa_die "review readiness requires current smoke status and evidence"
fi
if [[ "$STATUS" == complete ]]; then
  [[ "$STAGE" == complete && "$GATE" == none && "$EVIDENCE" == marker-readback ]] || aa_usage_die "walkthrough completion requires marker readback"
  "$ROOT/skills/first-time/scripts/validate-setup.sh" --root "$ROOT" --account-home "$ACCOUNT_HOME" --require-marker >/dev/null
elif [[ -e "$ROOT/.install-state/first-time-complete" || -L "$ROOT/.install-state/first-time-complete" ]]; then
  aa_die "a current completion marker must be validated or deliberately invalidated before reopening setup"
fi

LOCK="$STATE_DIR/.first-time-progress.lock"
[[ ! -L "$LOCK" ]] || aa_die "walkthrough progress lock is unsafe"
if ! /bin/mkdir -- "$LOCK" 2>/dev/null; then aa_die "another walkthrough progress update is active"; fi
/bin/chmod 700 "$LOCK"
cleanup_lock() {
  [[ -d "$LOCK" && ! -L "$LOCK" && "$(/usr/bin/stat -f '%u' "$LOCK")" == "$(/usr/bin/id -u)" ]] && /bin/rmdir -- "$LOCK" 2>/dev/null || true
}
trap cleanup_lock EXIT INT TERM

if [[ -e "$STATE" || -L "$STATE" ]]; then
  load_and_validate_record
  if [[ "$SMOKE_OBJECTIVE_ID" == none && "$saved_smoke" != none ]]; then
    SMOKE_OBJECTIVE_ID="$saved_smoke"
  fi
  if [[ ( "$saved_status" == waiting-user || "$saved_status" == pending-capability ) && "$saved_gate" != none ]]; then
    incoming_rank="$(stage_rank "$STAGE")"
    pending_rank="$(stage_rank "$saved_stage")"
    if [[ "$incoming_rank" != "$pending_rank" ]]; then
      STAGE="$saved_stage"
      STATUS="$saved_status"
      GATE="$saved_gate"
      EVIDENCE="$saved_evidence"
    elif [[ "$STATUS" == "$saved_status" && "$GATE" == "$saved_gate" && "$EVIDENCE" == "$saved_evidence" ]]; then
      : # Idempotent refresh of the same unresolved cursor.
    else
      [[ "$STATUS" == active && "$GATE" == none && "$EVIDENCE" == fresh-post-gate-readback ]] \
        || aa_die "walkthrough gate requires fresh post-gate readback at the blocked phase"
    fi
  fi
  STATE_BEFORE_SHA256="$(aa_sha256 "$STATE")"
else
  STATE_BEFORE_SHA256="absent"
fi

SETUP_CONFIG_SHA256="none"
if [[ -f "$ROOT/config/first-time.conf" && ! -L "$ROOT/config/first-time.conf" ]]; then
  SETUP_CONFIG_SHA256="$(aa_sha256 "$ROOT/config/first-time.conf")"
fi
TEMP="$STATE.tmp.$$"
[[ ! -e "$TEMP" && ! -L "$TEMP" ]] || aa_die "walkthrough temporary path is unsafe"
/usr/bin/printf 'WALKTHROUGH_VERSION=1\nROOT_SHA256=%s\nSTAGE=%s\nSTATUS=%s\nWAITING_GATE=%s\nEVIDENCE=%s\nSMOKE_OBJECTIVE_ID=%s\nSETUP_CONFIG_SHA256=%s\nUPDATED_AT=%s\n' \
  "$ROOT_SHA256" "$STAGE" "$STATUS" "$GATE" "$EVIDENCE" "$SMOKE_OBJECTIVE_ID" "$SETUP_CONFIG_SHA256" "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TEMP"
/bin/chmod 600 "$TEMP"
if [[ "$STATE_BEFORE_SHA256" == absent ]]; then
  [[ ! -e "$STATE" && ! -L "$STATE" ]] || aa_die "walkthrough progress changed during update"
else
  [[ -f "$STATE" && ! -L "$STATE" && "$(aa_sha256 "$STATE")" == "$STATE_BEFORE_SHA256" ]] || aa_die "walkthrough progress changed during update"
fi
/bin/mv -f -- "$TEMP" "$STATE"
/usr/bin/printf 'walkthrough stage=%s status=%s\n' "$STAGE" "$STATUS"
