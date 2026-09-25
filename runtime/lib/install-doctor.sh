#!/bin/zsh

set -u
umask 077

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/install-common.sh"

[[ $# -ge 2 && $# -le 3 ]] || aa_usage_die "usage: install-doctor.sh <root> <account-home> [--quiet|--json]"
ROOT="$1"
ACCOUNT_HOME="$2"
MODE="${3:---human}"
[[ "$MODE" == "--quiet" || "$MODE" == "--json" || "$MODE" == "--human" ]] || aa_usage_die "unknown doctor output mode: $MODE"
aa_safe_absolute_path "$ROOT" || aa_usage_die "root must be a safe absolute path"
aa_safe_absolute_path "$ACCOUNT_HOME" || aa_usage_die "account home must be a safe absolute path"
aa_require_child "$ROOT" "$ACCOUNT_HOME"
aa_reject_symlink_components "$ROOT"

INTEGRITY="healthy"
RUNTIME_STATUS="unavailable"
SETUP_STATE="incomplete"
SERVICE_STATE="not-configured"
SKILL_STATE="missing"
DETAIL=""
MANAGED_PROJECT_SKILLS=(
  first-time
  slack-inbox-triage
  messages-inbox-triage
  finish-the-mission
  remember-and-improve
  autobot-health-check
  delegate-and-verify
)

record_failure() {
  INTEGRITY="failed"
  if [[ -z "$DETAIL" ]]; then DETAIL="$1"; else DETAIL="$DETAIL; $1"; fi
}

[[ -d "$ROOT" && ! -L "$ROOT" ]] || record_failure "root missing or unsafe"
[[ -f "$ROOT/.install-state/managed-by-autoassist" && ! -L "$ROOT/.install-state/managed-by-autoassist" ]] || record_failure "ownership marker missing"
[[ -f "$ROOT/.install-state/installed-manifest.sha256" && ! -L "$ROOT/.install-state/installed-manifest.sha256" ]] || record_failure "installed manifest missing"
if [[ -d "$ROOT/.install-state" ]]; then
  [[ "$(/usr/bin/stat -f '%Lp' "$ROOT/.install-state")" == "700" ]] || record_failure "install-state mode is not 700"
fi

if [[ -f "$ROOT/.install-state/installed-manifest.sha256" ]]; then
  while IFS= read -r line; do
    expected="${line%%  *}"
    entry="${line#*  }"
    aa_safe_manifest_entry "$entry" || { record_failure "unsafe installed-manifest entry"; continue; }
    [[ -f "$ROOT/$entry" && ! -L "$ROOT/$entry" ]] || { record_failure "missing release file: $entry"; continue; }
    # Seed files are user-owned after installation and are intentionally mutable.
    if [[ -f "$ROOT/config/seed-manifest.txt" ]] && aa_is_seed "$ROOT/config/seed-manifest.txt" "$entry"; then continue; fi
    actual="$(aa_sha256 "$ROOT/$entry")"
    if [[ "$actual" != "$expected" && "$INTEGRITY" == "healthy" ]]; then INTEGRITY="customized"; fi
  done < "$ROOT/.install-state/installed-manifest.sha256"
fi

EXPECTED_INSTANCE=""
RECEIPT="$ROOT/.install-state/receipt.json"
if [[ -f "$RECEIPT" && ! -L "$RECEIPT" ]]; then
  EXPECTED_INSTANCE="$(/usr/bin/sed -n 's/.*"instance_id":"\([^"]*\)".*/\1/p' "$RECEIPT" | /usr/bin/head -1)"
fi
selected_skill_count=0
projected_skill_count=0
for managed_skill in "${MANAGED_PROJECT_SKILLS[@]}"; do
  canonical="$ROOT/skills/$managed_skill"
  project="$ROOT/.agents/skills/$managed_skill"
  marker="$project/.autoassist-skill"
  [[ -f "$canonical/SKILL.md" && ! -L "$canonical/SKILL.md" ]] || continue
  selected_skill_count=$((selected_skill_count + 1))
  if [[ ! -d "$project" || -L "$project" ]]; then
    record_failure "project-local skill projection missing: $managed_skill"
    continue
  fi
  projected_skill_count=$((projected_skill_count + 1))
  marker_ok=1
  [[ -f "$marker" && ! -L "$marker" ]] || marker_ok=0
  [[ "$marker_ok" -eq 0 || $(/usr/bin/grep -F -x -c 'managed-by=AutoAssist' "$marker" 2>/dev/null || true) -eq 1 ]] || marker_ok=0
  [[ "$marker_ok" -eq 0 || $(/usr/bin/grep -F -x -c "root=$ROOT" "$marker" 2>/dev/null || true) -eq 1 ]] || marker_ok=0
  if [[ -n "$EXPECTED_INSTANCE" ]]; then
    [[ "$marker_ok" -eq 0 || $(/usr/bin/grep -F -x -c "instance_id=$EXPECTED_INSTANCE" "$marker" 2>/dev/null || true) -eq 1 ]] || marker_ok=0
  fi
  if [[ "$managed_skill" != first-time ]]; then
    [[ "$marker_ok" -eq 0 || $(/usr/bin/grep -F -x -c "skill=$managed_skill" "$marker" 2>/dev/null || true) -eq 1 ]] || marker_ok=0
  fi
  if [[ "$marker_ok" -eq 0 ]]; then
    record_failure "project-local skill marker mismatch: $managed_skill"
    continue
  fi
  projected_digest="$(aa_tree_digest "$project" .autoassist-skill 2>/dev/null || true)"
  canonical_digest="$(aa_tree_digest "$canonical" 2>/dev/null || true)"
  [[ -n "$projected_digest" && "$projected_digest" == "$canonical_digest" ]] \
    || record_failure "project-local skill projection changed: $managed_skill"
done
if [[ "$selected_skill_count" -gt 0 && "$projected_skill_count" -eq "$selected_skill_count" ]]; then
  SKILL_STATE="project-local"
elif [[ "$projected_skill_count" -gt 0 ]]; then
  SKILL_STATE="partial"
fi
if [[ -f "$ROOT/.install-state/first-time-complete" && ! -L "$ROOT/.install-state/first-time-complete" ]]; then
  SETUP_STATE="complete-marker-present"
fi

if [[ "${AUTOASSIST_TEST_NODE_ABSENT:-0}" == "1" && ! -f "$ROOT/.install-state/test-mode" ]]; then
  record_failure "test-only Node override rejected outside test mode"
  unset AUTOASSIST_TEST_NODE_ABSENT
fi
aa_discover_node "$ROOT"
RUNTIME_STATUS="$AA_NODE_STATUS"

if [[ -f "$RECEIPT" && ! -L "$RECEIPT" ]]; then
  service_label="$(/usr/bin/sed -n 's/.*"service_label":"\([^"]*\)".*/\1/p' "$RECEIPT" | /usr/bin/head -1)"
  if [[ -n "$service_label" ]]; then
    plist="$ACCOUNT_HOME/Library/LaunchAgents/$service_label.plist"
    if [[ -f "$plist" && ! -L "$plist" ]]; then SERVICE_STATE="configured"; else SERVICE_STATE="receipt-only"; fi
  fi
fi

if [[ "$RUNTIME_STATUS" != "available" ]]; then SERVICE_STATE="not-configured-runtime-unavailable"; fi

if [[ "$MODE" == "--json" ]]; then
  /usr/bin/printf '{"installation_integrity":"%s","runtime_status":"%s","node_path":"%s","node_version":"%s","setup_state":"%s","service_state":"%s","skill_state":"%s","detail":"%s"}\n' \
    "$INTEGRITY" "$RUNTIME_STATUS" "$(aa_json_escape "$AA_NODE_PATH")" "$(aa_json_escape "$AA_NODE_VERSION")" \
    "$SETUP_STATE" "$SERVICE_STATE" "$SKILL_STATE" "$(aa_json_escape "$DETAIL")"
elif [[ "$MODE" != "--quiet" ]]; then
  /bin/echo "installation: $INTEGRITY"
  /bin/echo "runtime: $RUNTIME_STATUS${AA_NODE_VERSION:+ ($AA_NODE_VERSION)}"
  /bin/echo "setup: $SETUP_STATE"
  /bin/echo "service: $SERVICE_STATE"
  /bin/echo "skill: $SKILL_STATE"
  [[ -z "$DETAIL" ]] || /bin/echo "detail: $DETAIL"
fi

[[ "$INTEGRITY" != "failed" ]]
