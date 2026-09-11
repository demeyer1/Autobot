#!/bin/zsh

set -eu
umask 077

SCRIPT_ROOT="${0:A:h}"
source "$SCRIPT_ROOT/runtime/lib/install-common.sh"

ACCOUNT_HOME="${HOME:-}"
DESTINATION=""
TARGET_QUIESCENT=0

usage() {
  /bin/cat <<'EOF'
Usage: ./uninstall.sh [--home-root PATH] [--destination PATH] [--target-quiescent]

Moves one receipt-bound AutoAssist installation into the selected account
home's Trash. No user state is deleted, and HOME/CODEX_HOME are never changed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home-root) [[ $# -ge 2 && -n "$2" ]] || aa_usage_die "missing value for --home-root"; ACCOUNT_HOME="$2"; shift 2 ;;
    --destination) [[ $# -ge 2 && -n "$2" ]] || aa_usage_die "missing value for --destination"; DESTINATION="$2"; shift 2 ;;
    --target-quiescent) TARGET_QUIESCENT=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) aa_usage_die "unknown option: $1" ;;
  esac
done
[[ -n "$DESTINATION" ]] || DESTINATION="$ACCOUNT_HOME/AutoAssist"
aa_safe_absolute_path "$ACCOUNT_HOME" || aa_usage_die "home root must be a safe absolute path"
aa_safe_absolute_path "$DESTINATION" || aa_usage_die "destination must be a safe absolute path"
aa_require_child "$DESTINATION" "$ACCOUNT_HOME"
aa_reject_symlink_components "$ACCOUNT_HOME"
aa_reject_symlink_components "$DESTINATION"
[[ "$TARGET_QUIESCENT" -eq 1 ]] || aa_die "uninstall requires --target-quiescent"
[[ -d "$DESTINATION" && ! -L "$DESTINATION" ]] || aa_die "target is missing or unsafe"
[[ -f "$DESTINATION/.install-state/receipt.json" && ! -L "$DESTINATION/.install-state/receipt.json" ]] || aa_die "receipt is missing"
[[ -f "$DESTINATION/.install-state/managed-by-autoassist" && ! -L "$DESTINATION/.install-state/managed-by-autoassist" ]] || aa_die "ownership marker is missing"
/usr/bin/grep -F -x -q 'managed-by=AutoAssist' "$DESTINATION/.install-state/managed-by-autoassist" || aa_die "ownership marker is invalid"
aa_tree_has_unsafe_nodes "$DESTINATION" && aa_die "target contains a symlink or special file"

RECEIPT="$DESTINATION/.install-state/receipt.json"
receipt_root="$(/usr/bin/sed -n 's/.*"root":"\([^"]*\)".*/\1/p' "$RECEIPT" | /usr/bin/head -1)"
receipt_home="$(/usr/bin/sed -n 's/.*"account_home":"\([^"]*\)".*/\1/p' "$RECEIPT" | /usr/bin/head -1)"
instance_id="$(/usr/bin/sed -n 's/.*"instance_id":"\([^"]*\)".*/\1/p' "$RECEIPT" | /usr/bin/head -1)"
service_label="$(/usr/bin/sed -n 's/.*"service_label":"\([^"]*\)".*/\1/p' "$RECEIPT" | /usr/bin/head -1)"
plist_path="$(/usr/bin/sed -n 's/.*"plist_path":"\([^"]*\)".*/\1/p' "$RECEIPT" | /usr/bin/head -1)"
[[ "$receipt_root" == "$DESTINATION" && "$receipt_home" == "$ACCOUNT_HOME" ]] || aa_die "receipt scope does not match requested uninstall"
aa_safe_token "$instance_id" || aa_die "receipt instance is invalid"

LOCK="${DESTINATION:h}/.autoassist-install-$instance_id.lock"
/bin/mkdir "$LOCK" 2>/dev/null || aa_die "another lifecycle operation owns this instance"
/bin/chmod 700 "$LOCK"
cleanup() { /bin/rmdir "$LOCK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM HUP

if [[ -n "$service_label" ]]; then
  [[ "$service_label" == "io.autoprod.autobot.$instance_id" ]] || aa_die "receipt service label is not instance-bound"
  [[ "$plist_path" == "$ACCOUNT_HOME/Library/LaunchAgents/$service_label.plist" ]] || aa_die "receipt plist path is not instance-bound"
  aa_require_owned_directory "$ACCOUNT_HOME/Library/LaunchAgents" "$ACCOUNT_HOME"
  if [[ -f "$plist_path" && ! -L "$plist_path" ]]; then
    aa_plist_is_owned "$plist_path" "$service_label" "$DESTINATION" || aa_die "plist ownership mismatch"
    /bin/mkdir -p "$DESTINATION/.install-state/uninstalled-projections"
    /bin/cp -p "$plist_path" "$DESTINATION/.install-state/uninstalled-projections/"
    aa_stop_owned_service "$service_label" "$DESTINATION" || aa_die "managed service target mismatch or did not stop"
    /bin/rm -f "$plist_path"
  else
    aa_service_is_absent "$service_label" || aa_die "managed service remains active without its receipt-bound plist"
  fi
fi

# A legacy global skill is removed only when its marker binds this exact root and instance.
GLOBAL_SKILL="$ACCOUNT_HOME/.codex/skills/first-time"
aa_reject_symlink_components "$GLOBAL_SKILL"
aa_check_owned_ancestors "$GLOBAL_SKILL" "$ACCOUNT_HOME"
if [[ -f "$GLOBAL_SKILL/.autoassist-skill" && ! -L "$GLOBAL_SKILL/.autoassist-skill" ]] \
  && /usr/bin/grep -F -x -q "root=$DESTINATION" "$GLOBAL_SKILL/.autoassist-skill" \
  && /usr/bin/grep -F -x -q "instance_id=$instance_id" "$GLOBAL_SKILL/.autoassist-skill"; then
  /bin/mkdir -p "$DESTINATION/.install-state/uninstalled-projections"
  /bin/mv "$GLOBAL_SKILL" "$DESTINATION/.install-state/uninstalled-projections/global-first-time-skill"
fi

TRASH_DIR="$ACCOUNT_HOME/.Trash"
aa_require_owned_directory "$TRASH_DIR" "$ACCOUNT_HOME"
/bin/chmod 700 "$TRASH_DIR"
TRASH_TARGET="$TRASH_DIR/AutoAssist-uninstalled-$(/bin/date +%Y%m%d-%H%M%S)-$instance_id"
[[ ! -e "$TRASH_TARGET" ]] || aa_die "Trash destination already exists"
/bin/mv "$DESTINATION" "$TRASH_TARGET"
/bin/echo "Moved the receipt-bound AutoAssist installation to $TRASH_TARGET."
/bin/echo "Restore by moving it back to $DESTINATION while no writers are running."
