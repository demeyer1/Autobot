#!/bin/zsh

set -eu
setopt NO_NOMATCH
umask 077

SOURCE_ROOT="${0:A:h}"
ACCOUNT_HOME="${HOME:-}"
DESTINATION=""
DESTINATION_EXPLICIT=0
INSTANCE_ID=""
INSTANCE_ID_EXPLICIT=0
SKIP_LAUNCH_AGENT=1
LAUNCH_AGENT_CHOICE_EXPLICIT=0
ROLLBACK=0
TARGET_QUIESCENT=0
TEST_MODE=0
TEST_ROOT=""
FAILPOINT=""
LEGACY_ROLLBACK=0
SERVICE_LABEL=""
PLIST_PATH=""
PLIST_CREATED=0
PLIST_HAD_PRIOR=0
SERVICE_BOOTSTRAPPED=0
OLD_SERVICE_CONFIGURED=0
OLD_SERVICE_WAS_ACTIVE=0
OLD_SERVICE_PLIST=""
OLD_PLIST_REMOVED=0
INSTALL_MODE=""
PREVIOUS_BACKUP=""

# Project-local projections are selected from the release source, not from a
# release-version assumption.  Keep first-time first in the list because its
# receipt fields are part of the v0.4.0 compatibility contract.
MANAGED_PROJECT_SKILLS=(
  first-time
  slack-inbox-triage
  messages-inbox-triage
  finish-the-mission
  remember-and-improve
  autobot-health-check
  delegate-and-verify
)

source "$SOURCE_ROOT/runtime/lib/install-common.sh"

usage() {
  /bin/cat <<'EOF'
Usage: ./install.sh [options]

  --destination PATH      Install into PATH. Default: <home-root>/AutoAssist
  --home-root PATH        Bind user-scoped files without changing HOME.
  --instance-id TOKEN     Stable instance name (derived from destination by default).
  --enable-launch-agent   Opt in to the local LaunchAgent (requires Node 22+).
  --skip-launch-agent     Leave the LaunchAgent inactive, including on upgrade.
  --repair                Reconcile a managed installation transactionally.
  --rollback              Restore receipt-bound previous code, preserving current state.
  --target-quiescent      Assert all writers for an existing target are stopped.
  --test-mode             Enable isolated controls; requires --test-root.
  --test-root PATH        Owned disposable root for test mode.
  --failpoint NAME        Test-only interruption or late-writer simulation.
  --help                  Show this help.
EOF
}

need_value() { [[ $# -ge 2 && -n "$2" ]] || aa_usage_die "missing value for $1"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination) need_value "$@"; DESTINATION="$2"; DESTINATION_EXPLICIT=1; shift 2 ;;
    --home-root) need_value "$@"; ACCOUNT_HOME="$2"; shift 2 ;;
    --instance-id) need_value "$@"; INSTANCE_ID="$2"; INSTANCE_ID_EXPLICIT=1; shift 2 ;;
    --enable-launch-agent) SKIP_LAUNCH_AGENT=0; LAUNCH_AGENT_CHOICE_EXPLICIT=1; shift ;;
    --skip-launch-agent) SKIP_LAUNCH_AGENT=1; LAUNCH_AGENT_CHOICE_EXPLICIT=1; shift ;;
    --repair) shift ;; # Explicit spelling; reconciliation is always transactional.
    --rollback) ROLLBACK=1; shift ;;
    --target-quiescent) TARGET_QUIESCENT=1; shift ;;
    --test-mode) TEST_MODE=1; shift ;;
    --test-root) need_value "$@"; TEST_ROOT="$2"; shift 2 ;;
    --failpoint) need_value "$@"; FAILPOINT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) aa_usage_die "unknown option: $1" ;;
  esac
done

[[ -n "$ACCOUNT_HOME" ]] || aa_usage_die "home root must be explicit when HOME is unavailable"
[[ "$DESTINATION_EXPLICIT" -eq 1 ]] || DESTINATION="$ACCOUNT_HOME/AutoAssist"
aa_safe_absolute_path "$ACCOUNT_HOME" || aa_usage_die "home root must be a safe absolute path"
aa_safe_absolute_path "$DESTINATION" || aa_usage_die "destination must be a safe absolute path"
[[ -d "$ACCOUNT_HOME" && ! -L "$ACCOUNT_HOME" ]] || aa_die "home root must be an existing real directory"
aa_require_child "$DESTINATION" "$ACCOUNT_HOME"
aa_reject_symlink_components "$ACCOUNT_HOME"
aa_reject_symlink_components "$DESTINATION"

if [[ "$TEST_MODE" -eq 1 ]]; then
  aa_safe_absolute_path "$TEST_ROOT" || aa_usage_die "--test-mode requires a safe absolute --test-root"
  [[ -d "$TEST_ROOT" && ! -L "$TEST_ROOT" ]] || aa_usage_die "test root must be an existing real directory"
  [[ "$ACCOUNT_HOME" == "$TEST_ROOT"/* && "$DESTINATION" == "$TEST_ROOT"/* ]] || aa_usage_die "test home and destination must be descendants of test root"
else
  [[ -z "$TEST_ROOT" && -z "$FAILPOINT" && "${AUTOASSIST_TEST_NODE_ABSENT:-0}" != "1" ]] || aa_usage_die "test controls require --test-mode and --test-root"
fi
[[ -z "$FAILPOINT" || "$FAILPOINT" == "before-old-rename" || "$FAILPOINT" == "after-old-rename" || "$FAILPOINT" == "after-new-promote" || "$FAILPOINT" == "after-recovery-restore" || "$FAILPOINT" == "after-backup-finalize" || "$FAILPOINT" == "mutate-old-root-before-fingerprint" ]] || aa_usage_die "unknown failpoint"

if [[ "$INSTANCE_ID_EXPLICIT" -eq 0 && -f "$DESTINATION/.install-state/receipt.json" && ! -L "$DESTINATION/.install-state/receipt.json" ]]; then
  INSTANCE_ID="$(/usr/bin/sed -n 's/.*"instance_id":"\([^"]*\)".*/\1/p' "$DESTINATION/.install-state/receipt.json" | /usr/bin/head -1)"
fi
if [[ -z "$INSTANCE_ID" ]]; then
  INSTANCE_ID="$(/usr/bin/printf '%s' "$DESTINATION" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1,1,12)}')"
fi
aa_safe_token "$INSTANCE_ID" || aa_usage_die "instance id must be a bounded safe token"

PARENT="${DESTINATION:h}"
/bin/mkdir -p -- "$PARENT"
[[ -d "$PARENT" && ! -L "$PARENT" ]] || aa_die "destination parent is unsafe"
[[ "$(/usr/bin/stat -f '%u' "$PARENT")" == "$(/usr/bin/id -u)" ]] || aa_die "destination parent owner mismatch"
LOCK="$PARENT/.autoassist-install-$INSTANCE_ID.lock"
if ! /bin/mkdir -- "$LOCK" 2>/dev/null; then
  [[ -f "$LOCK/owner" && ! -L "$LOCK/owner" ]] || aa_die "another lifecycle operation owns $INSTANCE_ID"
  lock_pid="$(/usr/bin/awk -F= '$1 == "pid" { print $2; exit }' "$LOCK/owner")"
  [[ "$lock_pid" == <-> ]] || aa_die "lifecycle lock owner is invalid"
  if /bin/kill -0 "$lock_pid" 2>/dev/null; then aa_die "another lifecycle operation owns $INSTANCE_ID"; fi
  /bin/rm -rf -- "$LOCK"
  /bin/mkdir -- "$LOCK" 2>/dev/null || aa_die "another lifecycle operation acquired $INSTANCE_ID"
fi
/bin/chmod 700 "$LOCK"
/usr/bin/printf 'pid=%s\ninstance_id=%s\ndestination=%s\n' "$$" "$INSTANCE_ID" "$DESTINATION" > "$LOCK/owner"
/bin/chmod 600 "$LOCK/owner"

TRANSACTION=""
STAGE=""
OLD_ROOT=""
PROMOTED=0
PRESERVE_TRANSACTION=0

meta_value() {
  /usr/bin/awk -F= -v key="$2" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$1/meta"
}

receipt_value() {
  local receipt="$1"
  local key="$2"
  /usr/bin/sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" "$receipt" | /usr/bin/head -1
}

validate_service_projection_binding() {
  local label="$1"
  local plist="$2"
  [[ -n "$label" && ( "$label" == "io.autoprod.autobot.$INSTANCE_ID" || "$label" == "io.autoassist.supervisor" ) ]] || aa_die "pending service label is outside this installation"
  [[ "$plist" == "$ACCOUNT_HOME/Library/LaunchAgents/$label.plist" ]] || aa_die "pending service projection path mismatch"
  aa_require_owned_directory "$ACCOUNT_HOME/Library/LaunchAgents" "$ACCOUNT_HOME"
}

remove_deferred_old_projection() {
  local old_plist="$1"
  local current_plist="$2"
  [[ -n "$old_plist" && "$old_plist" != "$current_plist" && ( -e "$old_plist" || -L "$old_plist" ) ]] || return 0
  local old_label="${old_plist:t:r}"
  validate_service_projection_binding "$old_label" "$old_plist"
  aa_plist_is_owned "$old_plist" "$old_label" "$DESTINATION" || aa_die "deferred prior service projection ownership mismatch"
  if [[ "$TEST_MODE" -ne 1 || "$old_label" != io.autoassist.supervisor ]]; then
    aa_stop_owned_service "$old_label" "$DESTINATION" || aa_die "deferred prior service could not be stopped"
  fi
  /bin/rm -f -- "$old_plist"
}

restore_pending_projection() {
  local pending="$1"
  local label="$2"
  local plist="$3"
  local had_prior="$4"
  [[ -n "$label" || -n "$plist" ]] || return 0
  validate_service_projection_binding "$label" "$plist"
  if ! aa_service_is_absent "$label"; then
    aa_service_targets_root "$label" "$DESTINATION" || aa_die "pending service targets a different installation"
    aa_stop_owned_service "$label" "$DESTINATION" || aa_die "pending service could not be stopped"
  fi
  case "$had_prior" in
    1)
      [[ -f "$pending/plist-before" && ! -L "$pending/plist-before" ]] || aa_die "pending transaction lost its prior service projection"
      aa_plist_is_owned "$pending/plist-before" "$label" "$DESTINATION" || aa_die "pending prior service projection content mismatch"
      if [[ -e "$plist" || -L "$plist" ]]; then
        aa_plist_is_owned "$plist" "$label" "$DESTINATION" || aa_die "pending service projection ownership mismatch"
      fi
      /bin/cp -p -- "$pending/plist-before" "$plist"
      ;;
    0|"")
      if [[ -e "$plist" || -L "$plist" ]]; then
        aa_plist_is_owned "$plist" "$label" "$DESTINATION" || aa_die "pending service projection ownership mismatch"
        /bin/rm -f -- "$plist"
      fi
      ;;
    *) aa_die "pending service projection state is invalid" ;;
  esac
}

restore_pending_old_service() {
  local old_plist="$1"
  local was_active="$2"
  [[ "$was_active" == 1 ]] || return 0
  [[ -n "$old_plist" ]] || aa_die "pending transaction lost its active service projection"
  local old_label="${old_plist:t:r}"
  validate_service_projection_binding "$old_label" "$old_plist"
  aa_plist_is_owned "$old_plist" "$old_label" "$DESTINATION" || aa_die "prior service projection ownership mismatch"
  if aa_service_is_absent "$old_label"; then
    /bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$old_plist" >/dev/null 2>&1 || aa_die "prior service could not be restored"
  fi
  aa_service_targets_root "$old_label" "$DESTINATION" || aa_die "restored service target mismatch"
}

quarantine_pending_destination() {
  local quarantine
  quarantine="$(/usr/bin/mktemp -d "$PARENT/.AutoAssist-recovery-$INSTANCE_ID-XXXXXX")"
  /bin/rmdir -- "$quarantine"
  /bin/mv -- "$DESTINATION" "$quarantine"
}

restored_root_is_bound() {
  [[ -d "$DESTINATION" && ! -L "$DESTINATION" \
    && -f "$DESTINATION/.install-state/managed-by-autoassist" && ! -L "$DESTINATION/.install-state/managed-by-autoassist" \
    && -f "$DESTINATION/.install-state/migration.lock" && ! -L "$DESTINATION/.install-state/migration.lock" ]] \
    && /usr/bin/grep -F -x -q 'managed-by=AutoAssist' "$DESTINATION/.install-state/managed-by-autoassist" \
    && /usr/bin/grep -F -x -q "instance_id=$INSTANCE_ID" "$DESTINATION/.install-state/migration.lock"
}

rewrite_pending_phase() {
  local pending="$1"
  local phase="$2"
  local meta_temp="$pending/meta.tmp.$$"
  /usr/bin/printf 'destination=%s\ninstance_id=%s\ninstall_mode=%s\nphase=%s\nprevious_backup=%s\nold_service_plist=%s\nold_service_was_active=%s\nservice_label=%s\nplist_path=%s\nplist_had_prior=%s\n' \
    "$DESTINATION" "$INSTANCE_ID" "$(meta_value "$pending" install_mode)" "$phase" "$(meta_value "$pending" previous_backup)" \
    "$(meta_value "$pending" old_service_plist)" "$(meta_value "$pending" old_service_was_active)" \
    "$(meta_value "$pending" service_label)" "$(meta_value "$pending" plist_path)" "$(meta_value "$pending" plist_had_prior)" > "$meta_temp"
  /bin/chmod 600 "$meta_temp"
  /bin/mv -f -- "$meta_temp" "$pending/meta"
}

validate_pending_current() {
  local pending="$1"
  local backup="$2"
  [[ -d "$DESTINATION" && ! -L "$DESTINATION" ]] || aa_die "finalizing transaction lost its current root"
  [[ "$(/usr/bin/stat -f '%u' "$DESTINATION")" == "$(/usr/bin/id -u)" ]] || aa_die "finalizing current root owner mismatch"
  [[ -f "$DESTINATION/.install-state/managed-by-autoassist" && ! -L "$DESTINATION/.install-state/managed-by-autoassist" ]] || aa_die "finalizing current root ownership marker is missing"
  /usr/bin/grep -F -x -q 'managed-by=AutoAssist' "$DESTINATION/.install-state/managed-by-autoassist" || aa_die "finalizing current root ownership marker is invalid"
  local receipt="$DESTINATION/.install-state/receipt.json"
  [[ -f "$receipt" && ! -L "$receipt" ]] || aa_die "finalizing transaction has no durable receipt"
  [[ "$(receipt_value "$receipt" root)" == "$DESTINATION" \
    && "$(receipt_value "$receipt" account_home)" == "$ACCOUNT_HOME" \
    && "$(receipt_value "$receipt" instance_id)" == "$INSTANCE_ID" \
    && "$(receipt_value "$receipt" previous_backup)" == "$backup" ]] || aa_die "finalizing receipt scope mismatch"
  local receipt_label="$(receipt_value "$receipt" service_label)"
  local receipt_plist="$(receipt_value "$receipt" plist_path)"
  [[ "$receipt_label" == "$(meta_value "$pending" service_label)" && "$receipt_plist" == "$(meta_value "$pending" plist_path)" ]] || aa_die "finalizing service receipt mismatch"
  if [[ -n "$receipt_label" ]]; then
    validate_service_projection_binding "$receipt_label" "$receipt_plist"
    aa_plist_is_owned "$receipt_plist" "$receipt_label" "$DESTINATION" || aa_die "finalizing service projection ownership mismatch"
  else
    [[ -z "$receipt_plist" ]] || aa_die "finalizing receipt has an orphan service projection"
  fi
}

finalize_pending_transaction() {
  local pending="$1"
  local mode="$(meta_value "$pending" install_mode)"
  local backup="$(meta_value "$pending" previous_backup)"
  local old_plist="$(meta_value "$pending" old_service_plist)"
  validate_pending_current "$pending" "$backup"
  case "$mode" in
    fresh)
      [[ -z "$backup" && ! -e "$pending/old-root" ]] || aa_die "fresh finalizing transaction has an unexpected old root"
      ;;
    update)
      aa_safe_absolute_path "$backup" || aa_die "finalizing backup path is unsafe"
      [[ "${backup:h}" == "$PARENT/.AutoAssist-backups/$INSTANCE_ID" ]] || aa_die "finalizing backup path is outside this installation"
      aa_require_owned_directory "${backup:h}" "$PARENT"
      if [[ -e "$pending/old-root" && -e "$backup" ]]; then aa_die "finalizing transaction has two old roots"; fi
      if [[ -d "$pending/old-root" && ! -e "$backup" ]]; then /bin/mv -- "$pending/old-root" "$backup"; fi
      [[ ! -e "$pending/old-root" && -d "$backup" && ! -L "$backup" ]] || aa_die "finalizing transaction lost its exact previous backup"
      ;;
    *) aa_die "pending install mode is invalid" ;;
  esac
  local current_plist="$(receipt_value "$DESTINATION/.install-state/receipt.json" plist_path)"
  remove_deferred_old_projection "$old_plist" "$current_plist"
  rewrite_pending_phase "$pending" committed
  /bin/rm -rf -- "$pending"
}

cleanup() {
  local exit_code=$?
  local cleanup_ok=1
  local cleanup_phase=""
  if [[ -n "$TRANSACTION" && -f "$TRANSACTION/meta" ]]; then cleanup_phase="$(/usr/bin/awk -F= '$1 == "phase" { print $2; exit }' "$TRANSACTION/meta")"; fi
  if [[ "$exit_code" -ne 0 && "$cleanup_phase" != finalizing && "$cleanup_phase" != committed ]]; then
    if [[ "$SERVICE_BOOTSTRAPPED" -eq 1 && -n "$SERVICE_LABEL" ]]; then
      aa_stop_owned_service "$SERVICE_LABEL" "$DESTINATION" || cleanup_ok=0
    fi
    if [[ "$cleanup_ok" -eq 1 && "$PLIST_CREATED" -eq 1 ]]; then
      if [[ "$PLIST_HAD_PRIOR" -eq 1 ]]; then
        if [[ -f "$TRANSACTION/plist-before" && ! -L "$TRANSACTION/plist-before" ]] \
          && aa_plist_is_owned "$TRANSACTION/plist-before" "$SERVICE_LABEL" "$DESTINATION" \
          && { [[ ! -e "$PLIST_PATH" && ! -L "$PLIST_PATH" ]] || aa_plist_is_owned "$PLIST_PATH" "$SERVICE_LABEL" "$DESTINATION"; }; then
          /bin/cp -p "$TRANSACTION/plist-before" "$PLIST_PATH" 2>/dev/null || cleanup_ok=0
        else
          cleanup_ok=0
        fi
      else
        if [[ -e "$PLIST_PATH" || -L "$PLIST_PATH" ]]; then
          if aa_plist_is_owned "$PLIST_PATH" "$SERVICE_LABEL" "$DESTINATION"; then
            /bin/rm -f -- "$PLIST_PATH" 2>/dev/null || cleanup_ok=0
          else
            cleanup_ok=0
          fi
        fi
      fi
    fi
    if [[ "$cleanup_ok" -eq 1 && -n "$TRANSACTION" && -d "$OLD_ROOT" ]]; then
      rewrite_pending_phase "$TRANSACTION" restoring || cleanup_ok=0
    fi
    if [[ "$cleanup_ok" -eq 1 && "$PROMOTED" -eq 1 && -e "$DESTINATION" ]]; then
      failed_promoted="$PARENT/.AutoAssist-failed-promoted-$INSTANCE_ID-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$"
      /bin/mv -- "$DESTINATION" "$failed_promoted" 2>/dev/null || cleanup_ok=0
    fi
    if [[ "$cleanup_ok" -eq 1 && ! -e "$DESTINATION" && -n "$OLD_ROOT" && -d "$OLD_ROOT" ]]; then
      /bin/mv -- "$OLD_ROOT" "$DESTINATION" 2>/dev/null || cleanup_ok=0
    fi
    [[ "$cleanup_ok" -eq 0 || -e "$DESTINATION" || "$INSTALL_MODE" == fresh ]] || cleanup_ok=0
  elif [[ "$exit_code" -ne 0 ]]; then
    cleanup_ok=0
  fi
  if [[ "$exit_code" -ne 0 && "$cleanup_ok" -eq 1 && "$OLD_SERVICE_WAS_ACTIVE" -eq 1 ]]; then
    old_label="${OLD_SERVICE_PLIST:t:r}"
    if [[ -n "$OLD_SERVICE_PLIST" && "$OLD_SERVICE_PLIST" == "$ACCOUNT_HOME/Library/LaunchAgents/$old_label.plist" \
      && -f "$OLD_SERVICE_PLIST" && ! -L "$OLD_SERVICE_PLIST" ]] \
      && aa_plist_is_owned "$OLD_SERVICE_PLIST" "$old_label" "$DESTINATION"; then
      if aa_service_is_absent "$old_label"; then
        /bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$OLD_SERVICE_PLIST" >/dev/null 2>&1 || cleanup_ok=0
      fi
      [[ "$cleanup_ok" -eq 0 ]] || aa_service_targets_root "$old_label" "$DESTINATION" || cleanup_ok=0
    else
      cleanup_ok=0
    fi
  fi
  if [[ "$PRESERVE_TRANSACTION" -eq 0 && "$cleanup_ok" -eq 1 && -n "$TRANSACTION" && -d "$TRANSACTION" ]]; then /bin/rm -rf -- "$TRANSACTION"; fi
  if [[ "$cleanup_ok" -eq 1 ]]; then
    migration_lock="$DESTINATION/.install-state/migration.lock"
    if [[ -f "$migration_lock" && ! -L "$migration_lock" ]] && /usr/bin/grep -F -x -q "instance_id=$INSTANCE_ID" "$migration_lock"; then
      /bin/rm -f -- "$migration_lock"
    fi
  fi
  /bin/rm -rf -- "$LOCK" 2>/dev/null || true
  return "$exit_code"
}
trap cleanup EXIT INT TERM HUP

for pending in "$PARENT"/.autoassist-transaction-"$INSTANCE_ID"-*(N/); do
  [[ -f "$pending/meta" && ! -L "$pending/meta" ]] || aa_die "untrusted pending transaction: $pending"
  [[ ! -L "$pending" && "$(/usr/bin/stat -f '%u' "$pending")" == "$(/usr/bin/id -u)" ]] || aa_die "untrusted pending transaction owner: $pending"
  /usr/bin/grep -F -x -q "destination=$DESTINATION" "$pending/meta" || aa_die "pending transaction destination mismatch"
  pending_phase="$(/usr/bin/awk -F= '$1 == "phase" { print $2; exit }' "$pending/meta")"
  pending_mode="$(meta_value "$pending" install_mode)"
  pending_old_plist="$(meta_value "$pending" old_service_plist)"
  pending_old_active="$(meta_value "$pending" old_service_was_active)"
  pending_label="$(meta_value "$pending" service_label)"
  pending_plist="$(meta_value "$pending" plist_path)"
  pending_had_prior="$(meta_value "$pending" plist_had_prior)"
  case "$pending_phase" in
    staging)
      [[ ! -e "$pending/old-root" ]] || aa_die "staging transaction has an unexpected old root"
      if [[ "$pending_mode" == fresh ]]; then
        [[ ! -e "$DESTINATION" ]] || aa_die "fresh staging transaction collides with a destination"
      elif [[ "$pending_mode" == update ]]; then
        [[ -d "$DESTINATION" && ! -L "$DESTINATION" ]] || aa_die "update staging transaction lost its old root"
        restore_pending_old_service "$pending_old_plist" "$pending_old_active"
      else
        aa_die "pending install mode is invalid"
      fi
      /bin/rm -rf -- "$pending"
      ;;
    old-renamed)
      if [[ -e "$DESTINATION" && ! -e "$pending/old-root" ]]; then
        [[ "$pending_mode" == update ]] || aa_die "fresh transaction entered an update-only phase"
        restore_pending_old_service "$pending_old_plist" "$pending_old_active"
        /bin/rm -rf -- "$pending"
        continue
      fi
      [[ "$pending_mode" == update && ! -e "$DESTINATION" && -d "$pending/old-root" ]] || aa_die "old-renamed transaction has an ambiguous root tuple"
      /bin/mv -- "$pending/old-root" "$DESTINATION"
      restore_pending_old_service "$pending_old_plist" "$pending_old_active"
      /bin/rm -rf -- "$pending"
      ;;
    promoting|promoted)
      restore_pending_projection "$pending" "$pending_label" "$pending_plist" "$pending_had_prior"
      if [[ "$pending_mode" == update ]]; then
        [[ -d "$pending/old-root" ]] || aa_die "uncommitted update lost its old root"
        [[ ! -e "$DESTINATION" || -d "$DESTINATION" ]] || aa_die "uncommitted current root is unsafe"
        rewrite_pending_phase "$pending" restoring
        if [[ -e "$DESTINATION" ]]; then quarantine_pending_destination; fi
        /bin/mv -- "$pending/old-root" "$DESTINATION"
        if [[ "$FAILPOINT" == after-recovery-restore ]]; then
          PRESERVE_TRANSACTION=1
          trap - EXIT INT TERM HUP
          /bin/echo "test failpoint after-recovery-restore" >&2
          exit 95
        fi
        restore_pending_old_service "$pending_old_plist" "$pending_old_active"
      elif [[ "$pending_mode" == fresh ]]; then
        [[ ! -e "$pending/old-root" ]] || aa_die "fresh transaction has an unexpected old root"
        if [[ -e "$DESTINATION" ]]; then quarantine_pending_destination; fi
      else
        aa_die "pending install mode is invalid"
      fi
      /bin/rm -rf -- "$pending"
      ;;
    restoring)
      [[ "$pending_mode" == update ]] || aa_die "fresh transaction entered an update-only restore phase"
      if [[ -e "$DESTINATION" && -e "$pending/old-root" ]]; then aa_die "restoring transaction has two possible old roots"; fi
      if [[ ! -e "$DESTINATION" && -d "$pending/old-root" ]]; then
        /bin/mv -- "$pending/old-root" "$DESTINATION"
      elif [[ -e "$DESTINATION" && ! -e "$pending/old-root" ]]; then
        restored_root_is_bound || aa_die "restoring transaction cannot prove the current root identity"
      else
        aa_die "restoring transaction lost its old root"
      fi
      restore_pending_old_service "$pending_old_plist" "$pending_old_active"
      /bin/rm -rf -- "$pending"
      ;;
    activating)
      [[ -n "$pending_label" ]] || aa_die "activating transaction has no service"
      if aa_service_is_absent "$pending_label"; then
        restore_pending_projection "$pending" "$pending_label" "$pending_plist" "$pending_had_prior"
        if [[ "$pending_mode" == update ]]; then
          [[ -d "$pending/old-root" ]] || aa_die "uncommitted activation lost its old root"
          rewrite_pending_phase "$pending" restoring
          quarantine_pending_destination
          /bin/mv -- "$pending/old-root" "$DESTINATION"
          restore_pending_old_service "$pending_old_plist" "$pending_old_active"
        elif [[ "$pending_mode" == fresh ]]; then
          [[ ! -e "$pending/old-root" ]] || aa_die "fresh activation has an unexpected old root"
          quarantine_pending_destination
        else
          aa_die "pending install mode is invalid"
        fi
        /bin/rm -rf -- "$pending"
      else
        aa_service_targets_root "$pending_label" "$DESTINATION" || aa_die "activating service targets a different installation"
        validate_pending_current "$pending" "$(meta_value "$pending" previous_backup)"
        rewrite_pending_phase "$pending" finalizing
        finalize_pending_transaction "$pending"
      fi
      ;;
    finalizing|committed)
      finalize_pending_transaction "$pending"
      ;;
    *) aa_die "pending transaction phase is invalid" ;;
  esac
done

if [[ "$ROLLBACK" -eq 1 ]]; then
  [[ -f "$DESTINATION/.install-state/receipt.json" && ! -L "$DESTINATION/.install-state/receipt.json" ]] || aa_die "rollback requires a current receipt"
  rollback_source="$(/usr/bin/sed -n 's/.*"previous_backup":"\([^"]*\)".*/\1/p' "$DESTINATION/.install-state/receipt.json" | /usr/bin/head -1)"
  aa_safe_absolute_path "$rollback_source" || aa_die "receipt has no safe previous backup"
  aa_reject_symlink_components "$rollback_source"
  aa_check_owned_ancestors "$rollback_source" "$PARENT"
  [[ -d "$rollback_source" && ! -L "$rollback_source" ]] || aa_die "receipt-bound previous backup is unavailable"
  [[ "$(/usr/bin/stat -f '%u' "$rollback_source")" == "$(/usr/bin/id -u)" ]] || aa_die "rollback backup owner mismatch"
  current_schema=""
  previous_schema=""
  if [[ -f "$DESTINATION/state/core.json" && ! -L "$DESTINATION/state/core.json" ]]; then
    current_schema="$(/usr/bin/plutil -extract schema raw -o - "$DESTINATION/state/core.json" 2>/dev/null || true)"
  fi
  if [[ -f "$rollback_source/state/core.json" && ! -L "$rollback_source/state/core.json" ]]; then
    previous_schema="$(/usr/bin/plutil -extract schema raw -o - "$rollback_source/state/core.json" 2>/dev/null || true)"
  fi
  [[ -n "$current_schema" ]] || current_schema="$(/usr/bin/sed -n 's/.*"state_schema":\([0-9][0-9]*\).*/\1/p' "$DESTINATION/.install-state/receipt.json" | /usr/bin/head -1)"
  [[ -n "$previous_schema" ]] || previous_schema="$(/usr/bin/sed -n 's/.*"state_schema":\([0-9][0-9]*\).*/\1/p' "$rollback_source/.install-state/receipt.json" 2>/dev/null | /usr/bin/head -1)"
  [[ -n "$current_schema" ]] || current_schema=1
  [[ -n "$previous_schema" ]] || previous_schema=1
  [[ "$previous_schema" == "$current_schema" ]] || aa_die "rollback refused: state schema is incompatible"
  SOURCE_ROOT="$rollback_source"
  TARGET_QUIESCENT=1
  SKIP_LAUNCH_AGENT=1
  LAUNCH_AGENT_CHOICE_EXPLICIT=1
  [[ -x "$SOURCE_ROOT/runtime/lib/install-doctor.sh" ]] || LEGACY_ROLLBACK=1
fi

[[ "$DESTINATION" != "$SOURCE_ROOT" && "$SOURCE_ROOT" != "$DESTINATION"/* && "$DESTINATION" != "$SOURCE_ROOT"/* ]] || aa_die "destination intersects the release source"
[[ "$SOURCE_ROOT" != "$DESTINATION" ]] || aa_die "run the installer from release media, not from the target"
ALLOWLIST="$SOURCE_ROOT/config/release-allowlist.txt"
SEED_MANIFEST="$SOURCE_ROOT/config/seed-manifest.txt"
aa_validate_release_manifest "$SOURCE_ROOT" "$ALLOWLIST"
VERSION="$(/bin/cat "$SOURCE_ROOT/VERSION")"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || aa_die "release version is invalid"

skill_source_is_selected() {
  local skill="$1"
  local skill_root="$SOURCE_ROOT/skills/$skill"
  [[ -d "$skill_root" && ! -L "$skill_root" \
    && -f "$skill_root/SKILL.md" && ! -L "$skill_root/SKILL.md" ]]
}

validate_source_project_skill() {
  local skill="$1"
  local skill_root="$SOURCE_ROOT/skills/$skill"
  if [[ -L "$skill_root" || -e "$skill_root" ]]; then
    [[ -d "$skill_root" && ! -L "$skill_root" ]] || aa_die "managed skill source is unsafe: $skill"
    [[ -f "$skill_root/SKILL.md" && ! -L "$skill_root/SKILL.md" ]] \
      || aa_die "managed skill source is missing SKILL.md: $skill"
    aa_tree_has_unsafe_nodes "$skill_root" && aa_die "managed skill source contains unsafe nodes: $skill"
  fi
}

for managed_skill in "${MANAGED_PROJECT_SKILLS[@]}"; do
  validate_source_project_skill "$managed_skill"
done
skill_source_is_selected first-time || aa_die "release is missing required first-time skill"

INSTALL_MODE=fresh
OLD_MANIFEST=""
if [[ -e "$DESTINATION" ]]; then
  [[ -d "$DESTINATION" && ! -L "$DESTINATION" ]] || aa_die "existing destination is unsafe"
  [[ "$TARGET_QUIESCENT" -eq 1 ]] || aa_die "existing target requires --target-quiescent"
  [[ -f "$DESTINATION/.install-state/managed-by-autoassist" && ! -L "$DESTINATION/.install-state/managed-by-autoassist" ]] || aa_die "destination is not a managed AutoAssist installation"
  /usr/bin/grep -F -x -q 'managed-by=AutoAssist' "$DESTINATION/.install-state/managed-by-autoassist" || aa_die "ownership marker is invalid"
  [[ "$(/usr/bin/stat -f '%u' "$DESTINATION")" == "$(/usr/bin/id -u)" ]] || aa_die "target owner mismatch"
  aa_tree_has_unsafe_nodes "$DESTINATION" && aa_die "target contains a symlink or special file"
  INSTALL_MODE=update
  if [[ -f "$DESTINATION/.install-state/installed-manifest.sha256" && ! -L "$DESTINATION/.install-state/installed-manifest.sha256" ]]; then
    current_receipt="$DESTINATION/.install-state/receipt.json"
    [[ -f "$current_receipt" && ! -L "$current_receipt" ]] || aa_die "managed target receipt is missing"
    receipt_root="$(/usr/bin/sed -n 's/.*"root":"\([^"]*\)".*/\1/p' "$current_receipt" | /usr/bin/head -1)"
    receipt_home="$(/usr/bin/sed -n 's/.*"account_home":"\([^"]*\)".*/\1/p' "$current_receipt" | /usr/bin/head -1)"
    receipt_instance="$(/usr/bin/sed -n 's/.*"instance_id":"\([^"]*\)".*/\1/p' "$current_receipt" | /usr/bin/head -1)"
    [[ "$receipt_root" == "$DESTINATION" && "$receipt_home" == "$ACCOUNT_HOME" && "$receipt_instance" == "$INSTANCE_ID" ]] || aa_die "managed target receipt scope mismatch"
    old_service_label="$(/usr/bin/sed -n 's/.*"service_label":"\([^"]*\)".*/\1/p' "$current_receipt" | /usr/bin/head -1)"
    old_plist_path="$(/usr/bin/sed -n 's/.*"plist_path":"\([^"]*\)".*/\1/p' "$current_receipt" | /usr/bin/head -1)"
    if [[ -n "$old_service_label" ]]; then
      [[ "$old_service_label" == "io.autoprod.autobot.$INSTANCE_ID" && "$old_plist_path" == "$ACCOUNT_HOME/Library/LaunchAgents/$old_service_label.plist" ]] || aa_die "managed service receipt scope mismatch"
      aa_require_owned_directory "$ACCOUNT_HOME/Library/LaunchAgents" "$ACCOUNT_HOME"
      aa_plist_is_owned "$old_plist_path" "$old_service_label" "$DESTINATION" || aa_die "managed service projection ownership mismatch"
      aa_service_is_absent "$old_service_label" || OLD_SERVICE_WAS_ACTIVE=1
      aa_stop_owned_service "$old_service_label" "$DESTINATION" || aa_die "managed service target mismatch or did not stop"
      OLD_SERVICE_CONFIGURED=1
      OLD_SERVICE_PLIST="$old_plist_path"
    fi
    OLD_MANIFEST="$DESTINATION/.install-state/installed-manifest.sha256"
  else
    receipt="$DESTINATION/.install-state/receipt.txt"
    [[ -f "$receipt" && ! -L "$receipt" ]] || aa_die "legacy receipt is missing"
    /usr/bin/grep -F -x -q 'version=0.1.0' "$receipt" || aa_die "legacy receipt version is not recognized"
    /usr/bin/grep -F -x -q "path=$DESTINATION" "$receipt" || aa_die "legacy receipt path mismatch"
    [[ "$(aa_sha256 "$DESTINATION/VERSION")" == "9ca90d4ac8fbe86d8aca4aa37a80e0f984c01df281f25f62c779e784fd155a21" ]] || aa_die "legacy VERSION anchor mismatch"
    [[ "$(aa_sha256 "$DESTINATION/LICENSE")" == "a8323253d2ae9e1eb82372f057ecb64f7f9892bcb2e53db758e7097e2da1270b" ]] || aa_die "legacy LICENSE anchor mismatch"
    legacy_label="io.autoassist.supervisor"
    legacy_plist="$ACCOUNT_HOME/Library/LaunchAgents/$legacy_label.plist"
    aa_require_owned_directory "$ACCOUNT_HOME/Library/LaunchAgents" "$ACCOUNT_HOME"
    if [[ -e "$legacy_plist" ]]; then
      aa_plist_is_owned "$legacy_plist" "$legacy_label" "$DESTINATION" || aa_die "legacy service projection ownership mismatch"
      if [[ "$TEST_MODE" -eq 0 ]]; then
        aa_service_is_absent "$legacy_label" || OLD_SERVICE_WAS_ACTIVE=1
        aa_stop_owned_service "$legacy_label" "$DESTINATION" || aa_die "legacy service target mismatch or did not stop"
      fi
      OLD_SERVICE_CONFIGURED=1
      OLD_SERVICE_PLIST="$legacy_plist"
    else
      aa_service_is_absent "$legacy_label" || aa_die "legacy service is active without an owned projection"
    fi
  fi
fi

if [[ "$INSTALL_MODE" == update && "$OLD_SERVICE_CONFIGURED" -eq 1 && "$LAUNCH_AGENT_CHOICE_EXPLICIT" -eq 0 ]]; then
  SKIP_LAUNCH_AGENT=0
fi

if [[ "$INSTALL_MODE" == update ]]; then
  BACKUP_DIR="$PARENT/.AutoAssist-backups/$INSTANCE_ID"
  aa_require_owned_directory "$PARENT/.AutoAssist-backups" "$PARENT"
  aa_require_owned_directory "$BACKUP_DIR" "$PARENT"
  /bin/chmod 700 "$PARENT/.AutoAssist-backups" "$BACKUP_DIR"
fi
if [[ "$SKIP_LAUNCH_AGENT" -eq 0 ]]; then
  proposed_label="io.autoprod.autobot.$INSTANCE_ID"
  proposed_plist="$ACCOUNT_HOME/Library/LaunchAgents/$proposed_label.plist"
  aa_require_owned_directory "$ACCOUNT_HOME/Library/LaunchAgents" "$ACCOUNT_HOME"
  if [[ -e "$proposed_plist" ]]; then
    [[ "$OLD_SERVICE_CONFIGURED" -eq 1 && "$OLD_SERVICE_PLIST" == "$proposed_plist" ]] \
      && aa_plist_is_owned "$proposed_plist" "$proposed_label" "$DESTINATION" \
      || aa_die "same-instance service projection is not owned by this installation"
  fi
fi

payload_kb="$(/usr/bin/du -sk "$SOURCE_ROOT" | /usr/bin/awk '{print $1}')"
current_kb=0
[[ "$INSTALL_MODE" == update ]] && current_kb="$(/usr/bin/du -sk "$DESTINATION" | /usr/bin/awk '{print $1}')"
required_kb=$((payload_kb + current_kb + 1024))
available_kb="$(/bin/df -k "$PARENT" | /usr/bin/awk 'NR==2 {print $4}')"
[[ "$available_kb" == <-> && "$available_kb" -ge "$required_kb" ]] || aa_die "insufficient free space: need at least ${required_kb} KiB"

TRANSACTION="$(/usr/bin/mktemp -d "$PARENT/.autoassist-transaction-$INSTANCE_ID-XXXXXX")"
/bin/chmod 700 "$TRANSACTION"
STAGE="$TRANSACTION/stage"
OLD_ROOT="$TRANSACTION/old-root"
/usr/bin/printf 'destination=%s\ninstance_id=%s\ninstall_mode=%s\nphase=staging\nprevious_backup=\nold_service_plist=%s\nold_service_was_active=%s\nservice_label=\nplist_path=\nplist_had_prior=0\n' \
  "$DESTINATION" "$INSTANCE_ID" "$INSTALL_MODE" "$OLD_SERVICE_PLIST" "$OLD_SERVICE_WAS_ACTIVE" > "$TRANSACTION/meta"
/bin/chmod 600 "$TRANSACTION/meta"
set_phase() {
  local phase="$1"
  local backup="${2:-}"
  local meta_temp="$TRANSACTION/meta.tmp.$$"
  /usr/bin/printf 'destination=%s\ninstance_id=%s\ninstall_mode=%s\nphase=%s\nprevious_backup=%s\nold_service_plist=%s\nold_service_was_active=%s\nservice_label=%s\nplist_path=%s\nplist_had_prior=%s\n' \
    "$DESTINATION" "$INSTANCE_ID" "$INSTALL_MODE" "$phase" "$backup" "$OLD_SERVICE_PLIST" "$OLD_SERVICE_WAS_ACTIVE" \
    "$SERVICE_LABEL" "$PLIST_PATH" "$PLIST_HAD_PRIOR" > "$meta_temp"
  /bin/chmod 600 "$meta_temp"
  /bin/mv -f "$meta_temp" "$TRANSACTION/meta"
}
/bin/mkdir -p -- "$STAGE"
/bin/chmod 700 "$STAGE"
if [[ "$INSTALL_MODE" == update && -z "$OLD_MANIFEST" ]]; then
  aa_legacy_manifest "$TRANSACTION/legacy-v0.1.0.sha256"
  OLD_MANIFEST="$TRANSACTION/legacy-v0.1.0.sha256"
fi

fingerprint_tree() {
  local root="$1"
  local output="$2"
  (cd "$root" && /usr/bin/find -P . -type f ! -path './.install-state/migration.lock' -print | LC_ALL=C /usr/bin/sort | while IFS= read -r path; do
    /usr/bin/printf '%s  %s\n' "$(aa_sha256 "$root/${path#./}")" "${path#./}"
  done) > "$output"
}

record_project_skill_conflict() {
  /usr/bin/printf '%s\n' ".agents/skills/$1 ($2)" >> "$CONFLICTS"
}

validate_current_project_skill() {
  local skill="$1"
  local project="$DESTINATION/.agents/skills/$skill"
  local marker="$project/.autoassist-skill"
  local canonical="$DESTINATION/skills/$skill"
  local owned=1
  local projected_digest=""
  local canonical_digest=""
  local manifest_line=""
  local manifest_path=""

  if [[ ! -d "$project" || -L "$project" ]]; then
    record_project_skill_conflict "$skill" "project-local projection is unsafe"
    return 0
  fi
  [[ -f "$marker" && ! -L "$marker" ]] || owned=0
  [[ "$owned" -eq 0 || $(/usr/bin/grep -F -x -c "managed-by=AutoAssist" "$marker" 2>/dev/null || true) -eq 1 ]] || owned=0
  [[ "$owned" -eq 0 || $(/usr/bin/grep -F -x -c "root=$DESTINATION" "$marker" 2>/dev/null || true) -eq 1 ]] || owned=0
  [[ "$owned" -eq 0 || $(/usr/bin/grep -F -x -c "instance_id=$INSTANCE_ID" "$marker" 2>/dev/null || true) -eq 1 ]] || owned=0
  if [[ "$skill" != first-time ]]; then
    [[ "$owned" -eq 0 || $(/usr/bin/grep -F -x -c "skill=$skill" "$marker" 2>/dev/null || true) -eq 1 ]] || owned=0
  fi
  if [[ "$owned" -eq 0 ]]; then
    record_project_skill_conflict "$skill" "projection ownership mismatch"
    return 0
  fi
  if [[ ! -d "$canonical" || -L "$canonical" ]]; then
    record_project_skill_conflict "$skill" "canonical skill is missing"
    return 0
  fi
  while IFS= read -r manifest_line; do
    manifest_path="${manifest_line#*  }"
    [[ "$manifest_path" == "skills/$skill/"* ]] || continue
    aa_safe_manifest_entry "$manifest_path" || { record_project_skill_conflict "$skill" "unsafe old skill manifest"; return 0; }
    if [[ ! -f "$DESTINATION/$manifest_path" || -L "$DESTINATION/$manifest_path" ]]; then
      record_project_skill_conflict "$skill" "canonical skill file was removed"
      return 0
    fi
  done < "$OLD_MANIFEST"
  projected_digest="$(aa_tree_digest "$project" .autoassist-skill 2>/dev/null || true)"
  canonical_digest="$(aa_tree_digest "$canonical" 2>/dev/null || true)"
  [[ -n "$projected_digest" && "$projected_digest" == "$canonical_digest" ]] \
    || record_project_skill_conflict "$skill" "project-local skill was customized"
}

canonical_skill_matches_old_manifest() {
  local skill="$1"
  local canonical="$DESTINATION/skills/$skill"
  local path=""
  local relative=""
  local old_hash=""
  local actual_hash=""
  local line=""
  local found=0
  [[ -d "$canonical" && ! -L "$canonical" ]] || return 1
  while IFS= read -r path; do
    relative="${path#$DESTINATION/}"
    old_hash="$(aa_manifest_hash_for "$OLD_MANIFEST" "$relative" 2>/dev/null || true)"
    [[ -n "$old_hash" ]] || return 1
    actual_hash="$(aa_sha256 "$path")"
    [[ "$actual_hash" == "$old_hash" ]] || return 1
    found=1
  done < <(/usr/bin/find -P "$canonical" -type f -print | LC_ALL=C /usr/bin/sort)
  while IFS= read -r line; do
    relative="${line#*  }"
    [[ "$relative" == "skills/$skill/"* ]] || continue
    aa_safe_manifest_entry "$relative" || return 1
    [[ -f "$DESTINATION/$relative" && ! -L "$DESTINATION/$relative" ]] || return 1
  done < "$OLD_MANIFEST"
  [[ "$found" -eq 1 ]]
}

if [[ "$INSTALL_MODE" == update ]]; then
  /usr/bin/printf 'instance_id=%s\npid=%s\n' "$INSTANCE_ID" "$$" > "$DESTINATION/.install-state/migration.lock"
  /bin/chmod 600 "$DESTINATION/.install-state/migration.lock"
  fingerprint_tree "$DESTINATION" "$TRANSACTION/before.sha256"
  /bin/cp -Rp "$DESTINATION/." "$STAGE/"
else
  /bin/mkdir -p "$STAGE/.install-state"
fi

CONFLICTS="$TRANSACTION/conflicts.txt"
: > "$CONFLICTS"
while IFS= read -r entry; do
  [[ -z "$entry" || "$entry" == \#* ]] && continue
  source_file="$SOURCE_ROOT/$entry"
  staged_file="$STAGE/$entry"
  if [[ "$INSTALL_MODE" == fresh ]]; then aa_copy_file "$source_file" "$staged_file"; continue; fi
  if aa_is_seed "$SEED_MANIFEST" "$entry" && [[ -f "$DESTINATION/$entry" ]]; then continue; fi
  if [[ ! -e "$DESTINATION/$entry" ]]; then aa_copy_file "$source_file" "$staged_file"; continue; fi
  old_hash="$(aa_manifest_hash_for "$OLD_MANIFEST" "$entry" 2>/dev/null || true)"
  current_hash="$(aa_sha256 "$DESTINATION/$entry")"
  new_hash="$(aa_sha256 "$source_file")"
  if [[ -z "$old_hash" ]]; then
    /usr/bin/printf '%s\n' "$entry (new release path collides with an unowned file)" >> "$CONFLICTS"
  elif [[ "$current_hash" == "$old_hash" ]]; then
    aa_copy_file "$source_file" "$staged_file"
  elif [[ "$new_hash" == "$old_hash" || "$current_hash" == "$new_hash" ]]; then
    : # Preserve customization or already-reconciled bytes.
  else
    /usr/bin/printf '%s\n' "$entry (both user and release changed it)" >> "$CONFLICTS"
  fi
done < "$ALLOWLIST"

if [[ "$INSTALL_MODE" == update ]]; then
  while IFS= read -r line; do
    old_hash="${line%%  *}"
    entry="${line#*  }"
    aa_safe_manifest_entry "$entry" || aa_die "unsafe old manifest entry"
    if ! aa_manifest_contains "$ALLOWLIST" "$entry" && [[ -f "$DESTINATION/$entry" && ! -L "$DESTINATION/$entry" ]]; then
      [[ "$(aa_sha256 "$DESTINATION/$entry")" != "$old_hash" ]] || /bin/rm -f -- "$STAGE/$entry"
    fi
  done < "$OLD_MANIFEST"
  for managed_skill in "${MANAGED_PROJECT_SKILLS[@]}"; do
    CURRENT_PROJECT_SKILL="$DESTINATION/.agents/skills/$managed_skill"
    if [[ -e "$CURRENT_PROJECT_SKILL" || -L "$CURRENT_PROJECT_SKILL" ]]; then
      validate_current_project_skill "$managed_skill"
      if ! skill_source_is_selected "$managed_skill" \
        && ! canonical_skill_matches_old_manifest "$managed_skill"; then
        record_project_skill_conflict "$managed_skill" "canonical skill was customized"
      fi
    fi
  done
fi
if [[ -s "$CONFLICTS" ]]; then
  /bin/echo "AutoAssist update stopped before mutation. Resolve these three-way conflicts:" >&2
  /bin/cat "$CONFLICTS" >&2
  aa_die "no target files were changed"
fi

/bin/mkdir -p -- "$STAGE/.agents/skills"
for managed_skill in "${MANAGED_PROJECT_SKILLS[@]}"; do
  if skill_source_is_selected "$managed_skill"; then
    /bin/rm -rf -- "$STAGE/.agents/skills/$managed_skill"
    [[ -d "$STAGE/skills/$managed_skill" && -f "$STAGE/skills/$managed_skill/SKILL.md" ]] \
      || aa_die "selected release skill was not staged: $managed_skill"
    /bin/cp -Rp -- "$STAGE/skills/$managed_skill" "$STAGE/.agents/skills/$managed_skill"
    if [[ "$managed_skill" == first-time ]]; then
      /usr/bin/printf 'managed-by=AutoAssist\nroot=%s\ninstance_id=%s\n' \
        "$DESTINATION" "$INSTANCE_ID" > "$STAGE/.agents/skills/$managed_skill/.autoassist-skill"
    else
      /usr/bin/printf 'managed-by=AutoAssist\nroot=%s\ninstance_id=%s\nskill=%s\n' \
        "$DESTINATION" "$INSTANCE_ID" "$managed_skill" > "$STAGE/.agents/skills/$managed_skill/.autoassist-skill"
    fi
  elif [[ "$INSTALL_MODE" == update && ( -e "$STAGE/.agents/skills/$managed_skill" || -L "$STAGE/.agents/skills/$managed_skill" ) ]]; then
    # The preflight above proved both marker ownership and pristine canonical
    # bytes before an omitted skill is removed (especially during rollback).
    /bin/rm -rf -- "$STAGE/.agents/skills/$managed_skill"
  fi
done
/bin/mkdir -p "$STAGE/.install-state" "$STAGE/00_CONTEXT" "$STAGE/01_PROJECTS" "$STAGE/02_INBOX" "$STAGE/03_OUTPUTS"
/bin/chmod 700 "$STAGE" "$STAGE/.install-state" "$STAGE/.agents" "$STAGE/.agents/skills" "$STAGE/.agents/skills/first-time" "$STAGE/00_CONTEXT" "$STAGE/01_PROJECTS" "$STAGE/02_INBOX" "$STAGE/03_OUTPUTS"
/usr/bin/printf '%s\n' 'managed-by=AutoAssist' > "$STAGE/.install-state/managed-by-autoassist"
[[ "$TEST_MODE" -eq 0 ]] || /usr/bin/printf 'test_root=%s\n' "$TEST_ROOT" > "$STAGE/.install-state/test-mode"
/bin/chmod 600 "$STAGE/.install-state/managed-by-autoassist"
for managed_skill in "${MANAGED_PROJECT_SKILLS[@]}"; do
  if [[ -d "$STAGE/.agents/skills/$managed_skill" ]]; then
    /bin/chmod 700 "$STAGE/.agents/skills/$managed_skill"
    /bin/chmod 600 "$STAGE/.agents/skills/$managed_skill/.autoassist-skill"
  fi
done
[[ ! -f "$STAGE/.install-state/test-mode" ]] || /bin/chmod 600 "$STAGE/.install-state/test-mode"
[[ -f "$STAGE/config/profile.conf" ]] || aa_copy_file "$STAGE/config/profile.example.conf" "$STAGE/config/profile.conf"
/bin/chmod 600 "$STAGE/config/profile.conf"
for zone in PRIVATE FAMILY_FRIENDS WORK SHARED; do
  /bin/mkdir -p "$STAGE/00_CONTEXT/$zone"
  [[ -f "$STAGE/00_CONTEXT/$zone/INDEX.md" ]] || /usr/bin/printf '# %s\n\nOwner-only local index.\n' "$zone" > "$STAGE/00_CONTEXT/$zone/INDEX.md"
  /bin/chmod 700 "$STAGE/00_CONTEXT/$zone"
  /bin/chmod 600 "$STAGE/00_CONTEXT/$zone/INDEX.md"
done

if [[ "$ROLLBACK" -eq 1 && -f "$SOURCE_ROOT/.install-state/installed-manifest.sha256" && ! -L "$SOURCE_ROOT/.install-state/installed-manifest.sha256" ]]; then
  /bin/cp -p "$SOURCE_ROOT/.install-state/installed-manifest.sha256" "$STAGE/.install-state/installed-manifest.sha256"
  /bin/chmod 600 "$STAGE/.install-state/installed-manifest.sha256"
else
  aa_generate_manifest "$SOURCE_ROOT" "$ALLOWLIST" "$STAGE/.install-state/installed-manifest.sha256"
fi
for executable in Install.command install.sh uninstall.sh runtime/bin/autoassist runtime/lib/common.sh runtime/lib/install-common.sh runtime/lib/install-doctor.sh skills/first-time/scripts/validate-setup.sh skills/first-time/scripts/walkthrough-progress.sh skills/first-time/scripts/write-status.sh; do
  [[ ! -f "$STAGE/$executable" ]] || /bin/chmod 700 "$STAGE/$executable"
done

if [[ "$INSTALL_MODE" == update ]]; then
  fingerprint_tree "$DESTINATION" "$TRANSACTION/after-stage.sha256"
  /usr/bin/cmp -s "$TRANSACTION/before.sha256" "$TRANSACTION/after-stage.sha256" || aa_die "target changed while migration was staged"
  /bin/rm -f "$STAGE/.install-state/migration.lock"
  set_phase old-renamed
  if [[ "$FAILPOINT" == before-old-rename ]]; then
    PRESERVE_TRANSACTION=1
    trap - EXIT INT TERM HUP
    /bin/echo "test failpoint before-old-rename" >&2
    exit 96
  fi
  /bin/mv -- "$DESTINATION" "$OLD_ROOT"
  if [[ "$FAILPOINT" == mutate-old-root-before-fingerprint ]]; then
    /bin/mkdir -p "$OLD_ROOT/state"
    /usr/bin/printf 'late-writer-delta\n' > "$OLD_ROOT/state/test-late-writer"
  fi
  fingerprint_tree "$OLD_ROOT" "$TRANSACTION/after-old-rename.sha256"
  /usr/bin/cmp -s "$TRANSACTION/before.sha256" "$TRANSACTION/after-old-rename.sha256" || aa_die "old root changed during final migration handoff"
  if [[ "$FAILPOINT" == after-old-rename ]]; then
    PRESERVE_TRANSACTION=1
    trap - EXIT INT TERM HUP
    /bin/echo "test failpoint after-old-rename" >&2
    exit 97
  fi
fi
set_phase promoting
/bin/mv -- "$STAGE" "$DESTINATION"
PROMOTED=1
set_phase promoted
if [[ "$FAILPOINT" == after-new-promote ]]; then
  PRESERVE_TRANSACTION=1
  trap - EXIT INT TERM HUP
  /bin/echo "test failpoint after-new-promote" >&2
  exit 98
fi

if [[ "${AUTOASSIST_TEST_NODE_ABSENT:-0}" == 1 && "$TEST_MODE" -ne 1 ]]; then aa_die "Node test override escaped test mode"; fi
aa_discover_node "$DESTINATION"
PREVIOUS_BACKUP=""
if [[ "$INSTALL_MODE" == update ]]; then
  PREVIOUS_BACKUP="$BACKUP_DIR/$(/bin/date -u +%Y%m%dT%H%M%SZ)-$VERSION-$$"
fi
if [[ "$AA_NODE_STATUS" == available && "$SKIP_LAUNCH_AGENT" -eq 0 ]]; then
  SERVICE_LABEL="io.autoprod.autobot.$INSTANCE_ID"
  PLIST_PATH="$ACCOUNT_HOME/Library/LaunchAgents/$SERVICE_LABEL.plist"
  aa_require_owned_directory "${PLIST_PATH:h}" "$ACCOUNT_HOME"
  if [[ -e "$PLIST_PATH" ]]; then
    [[ "$OLD_SERVICE_CONFIGURED" -eq 1 && "$OLD_SERVICE_PLIST" == "$PLIST_PATH" ]] \
      && aa_plist_is_owned "$PLIST_PATH" "$SERVICE_LABEL" "$DESTINATION" \
      || aa_die "existing same-instance service projection is not owned by this installation"
    /bin/cp -p "$PLIST_PATH" "$TRANSACTION/plist-before"
    PLIST_HAD_PRIOR=1
  fi
  PLIST_CREATED=1
  set_phase promoted "$PREVIOUS_BACKUP"
  /usr/bin/sed -e "s|__SERVICE_LABEL__|$SERVICE_LABEL|g" -e "s|__AUTOASSIST_HOME__|$DESTINATION|g" -e "s|__ACCOUNT_HOME__|$ACCOUNT_HOME|g" "$DESTINATION/runtime/templates/io.autoassist.supervisor.plist.template" > "$PLIST_PATH.tmp.$$"
  /bin/chmod 600 "$PLIST_PATH.tmp.$$"
  /usr/bin/plutil -lint "$PLIST_PATH.tmp.$$" >/dev/null
  /bin/mv -f "$PLIST_PATH.tmp.$$" "$PLIST_PATH"
fi

if [[ "$LEGACY_ROLLBACK" -eq 0 ]]; then
  "$DESTINATION/runtime/lib/install-doctor.sh" "$DESTINATION" "$ACCOUNT_HOME" --quiet
else
  while IFS= read -r line; do
    expected_hash="${line%%  *}"
    installed_entry="${line#*  }"
    [[ -f "$DESTINATION/$installed_entry" && ! -L "$DESTINATION/$installed_entry" ]] || aa_die "legacy rollback verification found a missing file"
    if aa_is_seed "$DESTINATION/config/seed-manifest.txt" "$installed_entry"; then continue; fi
    [[ "$(aa_sha256 "$DESTINATION/$installed_entry")" == "$expected_hash" ]] || aa_die "legacy rollback verification found a changed release file"
  done < "$DESTINATION/.install-state/installed-manifest.sha256"
fi
MANIFEST_DIGEST="$(aa_sha256 "$DESTINATION/.install-state/installed-manifest.sha256")"
SKILL_DIGEST="$(aa_sha256 "$DESTINATION/.agents/skills/first-time/.autoassist-skill")"
RECEIPT_TEMP="$DESTINATION/.install-state/receipt.json.tmp.$$"
if [[ -n "$SERVICE_LABEL" ]]; then set_phase activating "$PREVIOUS_BACKUP"; fi
/usr/bin/printf '{"schema":2,"product_id":"Autobot","version":"%s","root":"%s","account_home":"%s","owner_uid":%s,"instance_id":"%s","release_manifest_sha256":"%s","service_label":"%s","plist_path":"%s","skill_path":"%s","skill_digest":"%s","node_status":"%s","node_path":"%s","node_version":"%s","state_schema":2,"previous_backup":"%s","installed_at":"%s"}\n' "$VERSION" "$DESTINATION" "$ACCOUNT_HOME" "$(/usr/bin/id -u)" "$INSTANCE_ID" "$MANIFEST_DIGEST" "$SERVICE_LABEL" "$PLIST_PATH" "$DESTINATION/.agents/skills/first-time" "$SKILL_DIGEST" "$AA_NODE_STATUS" "$(aa_json_escape "$AA_NODE_PATH")" "$(aa_json_escape "$AA_NODE_VERSION")" "$PREVIOUS_BACKUP" "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RECEIPT_TEMP"
/bin/chmod 600 "$RECEIPT_TEMP"
/bin/mv -f "$RECEIPT_TEMP" "$DESTINATION/.install-state/receipt.json"
if [[ -n "$SERVICE_LABEL" ]]; then
  GUI_DOMAIN="gui/$(/usr/bin/id -u)"
  /bin/launchctl bootstrap "$GUI_DOMAIN" "$PLIST_PATH"
  SERVICE_BOOTSTRAPPED=1
fi
set_phase finalizing "$PREVIOUS_BACKUP"
if [[ "$INSTALL_MODE" == update ]]; then
  /bin/mv -- "$OLD_ROOT" "$PREVIOUS_BACKUP"
fi
if [[ "$FAILPOINT" == after-backup-finalize ]]; then
  PRESERVE_TRANSACTION=1
  trap - EXIT INT TERM HUP
  /bin/echo "test failpoint after-backup-finalize" >&2
  exit 99
fi
if [[ -n "$OLD_SERVICE_PLIST" && "$OLD_SERVICE_PLIST" != "$PLIST_PATH" ]]; then
  remove_deferred_old_projection "$OLD_SERVICE_PLIST" "$PLIST_PATH"
  OLD_PLIST_REMOVED=1
fi
set_phase committed "$PREVIOUS_BACKUP"
PROMOTED=0
/bin/rm -rf -- "$TRANSACTION"
TRANSACTION=""

/bin/echo "AutoAssist $VERSION installed at $DESTINATION."
if [[ "$AA_NODE_STATUS" == available ]]; then
  /bin/echo "Advanced runtime: available ($AA_NODE_VERSION)."
else
  /bin/echo "Base installation: healthy. Advanced runtime: $AA_NODE_STATUS; select supported Node 22+ before scheduling."
fi
/bin/echo "Next: open $DESTINATION as a local project and run the project-local first-time skill."
