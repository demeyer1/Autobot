#!/bin/zsh
set -eu
umask 077
SOURCE_ROOT="${0:A:h:h}"
TEMP_PARENT="${TMPDIR:-/tmp}"; TEMP_PARENT="${TEMP_PARENT%/}"
TEST_ROOT="$(/usr/bin/mktemp -d "$TEMP_PARENT/autoassist-install-interruption.XXXXXX")"
TEST_ROOT="${TEST_ROOT:A}"
ACCOUNT_HOME="$TEST_ROOT/home"
DESTINATION="$ACCOUNT_HOME/AutoAssist"
cleanup() { local s=$?; [[ -d "$TEST_ROOT" ]] && /bin/rm -rf "$TEST_ROOT"; return "$s"; }
trap cleanup EXIT INT TERM
/bin/mkdir -p "$ACCOUNT_HOME"
FRESH_PENDING="$ACCOUNT_HOME/.autoassist-transaction-interruption-fresh"
/bin/mkdir -p "$FRESH_PENDING/stage"
/usr/bin/printf 'destination=%s\ninstance_id=interruption\ninstall_mode=fresh\nphase=staging\nprevious_backup=\nold_service_plist=\nold_service_was_active=0\nservice_label=\nplist_path=\nplist_had_prior=0\n' "$DESTINATION" > "$FRESH_PENDING/meta"
/bin/chmod 700 "$FRESH_PENDING" "$FRESH_PENDING/stage"
/bin/chmod 600 "$FRESH_PENDING/meta"
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/initial.log"
[[ ! -e "$FRESH_PENDING" ]] || { /bin/echo "fresh staging journal was not recovered" >&2; exit 1; }
if AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" --failpoint mutate-old-root-before-fingerprint > "$TEST_ROOT/late-writer.log" 2>&1; then /bin/echo "late writer delta was not detected" >&2; exit 1; fi
[[ -f "$DESTINATION/state/test-late-writer" && ! -e "$DESTINATION/.install-state/migration.lock" ]] || { /bin/echo "late writer delta was not restored with old root" >&2; exit 1; }
set +e
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" --failpoint before-old-rename > "$TEST_ROOT/before-rename.log" 2>&1
before_rename_status=$?
set -e
[[ "$before_rename_status" == 96 && -d "$DESTINATION" ]] || { /bin/echo "pre-rename journal failpoint changed the target" >&2; exit 1; }
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/before-rename-recovery.log"
set +e
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" --failpoint after-old-rename > "$TEST_ROOT/failpoint.log" 2>&1
fail_status=$?
set -e
[[ "$fail_status" == 97 && ! -e "$DESTINATION" ]] || { /bin/echo "failpoint did not leave recoverable journal" >&2; exit 1; }
[[ "$(/usr/bin/find "$ACCOUNT_HOME" -mindepth 1 -maxdepth 1 -type d -name '.autoassist-transaction-interruption-*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" == 1 ]]
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/recovery.log"
[[ -f "$DESTINATION/.install-state/receipt.json" ]]
[[ "$(/usr/bin/find "$ACCOUNT_HOME" -mindepth 1 -maxdepth 1 -type d -name '.autoassist-transaction-interruption-*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" == 0 ]] || { /bin/echo "recovery left pending transaction" >&2; exit 1; }
set +e
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" --failpoint after-new-promote > "$TEST_ROOT/promoted-failpoint.log" 2>&1
promoted_status=$?
set -e
[[ "$promoted_status" == 98 && -d "$DESTINATION" ]] || { /bin/echo "promoted failpoint did not preserve both trees" >&2; exit 1; }
set +e
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" --failpoint after-recovery-restore > "$TEST_ROOT/restoring-failpoint.log" 2>&1
restoring_status=$?
set -e
[[ "$restoring_status" == 95 && -d "$DESTINATION" ]] || { /bin/echo "recovery restore failpoint did not preserve the restored root" >&2; exit 1; }
RESTORING_PENDING="$(/usr/bin/find "$ACCOUNT_HOME" -mindepth 1 -maxdepth 1 -type d -name '.autoassist-transaction-interruption-*' -print -quit)"
[[ -n "$RESTORING_PENDING" && "$(/usr/bin/awk -F= '$1 == "phase" { print $2; exit }' "$RESTORING_PENDING/meta")" == restoring ]] || { /bin/echo "restoring journal phase is missing" >&2; exit 1; }
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/promoted-recovery.log"
[[ -f "$DESTINATION/.install-state/receipt.json" ]]
[[ "$(/usr/bin/find "$ACCOUNT_HOME" -mindepth 1 -maxdepth 1 -type d -name '.AutoAssist-recovery-interruption-*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" == 1 ]] || { /bin/echo "promoted recovery did not quarantine the uncommitted new tree" >&2; exit 1; }
/usr/bin/printf 'current-state-survives-finalization\n' > "$DESTINATION/state/finalization-sentinel"
recovery_count_before="$(/usr/bin/find "$ACCOUNT_HOME" -mindepth 1 -maxdepth 1 -type d -name '.AutoAssist-recovery-interruption-*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
set +e
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" --failpoint after-backup-finalize > "$TEST_ROOT/finalizing-failpoint.log" 2>&1
finalizing_status=$?
set -e
[[ "$finalizing_status" == 99 && -f "$DESTINATION/state/finalization-sentinel" ]] || { /bin/echo "backup-finalization failpoint lost the current root" >&2; exit 1; }
FINALIZING_PENDING="$(/usr/bin/find "$ACCOUNT_HOME" -mindepth 1 -maxdepth 1 -type d -name '.autoassist-transaction-interruption-*' -print -quit)"
[[ -n "$FINALIZING_PENDING" && "$(/usr/bin/awk -F= '$1 == "phase" { print $2; exit }' "$FINALIZING_PENDING/meta")" == finalizing ]] || { /bin/echo "backup-finalization journal phase is missing" >&2; exit 1; }
FINALIZED_BACKUP="$(/usr/bin/awk -F= '$1 == "previous_backup" { sub(/^[^=]*=/, ""); print; exit }' "$FINALIZING_PENDING/meta")"
[[ -d "$FINALIZED_BACKUP" && ! -e "$FINALIZING_PENDING/old-root" ]] || { /bin/echo "backup-finalization boundary tuple is incorrect" >&2; exit 1; }
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id interruption --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/finalizing-recovery.log"
[[ -f "$DESTINATION/state/finalization-sentinel" ]] || { /bin/echo "finalizing recovery replaced current mutable state" >&2; exit 1; }
[[ "$(/usr/bin/find "$ACCOUNT_HOME" -mindepth 1 -maxdepth 1 -type d -name '.AutoAssist-recovery-interruption-*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" == "$recovery_count_before" ]] || { /bin/echo "finalizing recovery quarantined the valid current root" >&2; exit 1; }
[[ "$DESTINATION/.install-state/receipt.json" -nt "$FINALIZED_BACKUP/.install-state/receipt.json" ]] || { /bin/echo "finalizing recovery did not continue through a fresh transaction" >&2; exit 1; }
/bin/echo "Interrupted fresh staging, pre-rename, old-renamed, promoted-swap, and backup-finalization recovery passed."
