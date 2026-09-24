#!/bin/zsh

set -eu
umask 077

SCRIPT_DIR="${0:A:h}"
AUTOASSIST_ROOT="${SCRIPT_DIR:h:h:h}"
ACCOUNT_HOME="${AUTOASSIST_ACCOUNT_HOME:-${HOME:-}}"
STATE=""
PROJECTS_TEMP=""
STATUS_TEMP=""

usage() {
  /bin/cat <<'EOF'
Usage: write-status.sh --state pending|complete [--root PATH] [--account-home PATH]

Writes only AutoAssist's generated first-time status file and its one command-
center entry. The complete state is accepted only after the current completion
marker passes first-time setup validation.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      [[ $# -ge 2 ]] || { /bin/echo "Missing value for --state" >&2; exit 2; }
      STATE="$2"
      shift 2
      ;;
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

if [[ "$STATE" != "pending" && "$STATE" != "complete" ]]; then
  /bin/echo "--state must be pending or complete" >&2
  exit 2
fi
if [[ ! -d "$AUTOASSIST_ROOT" || -L "$AUTOASSIST_ROOT" ]]; then
  /bin/echo "AutoAssist root must be a real directory: $AUTOASSIST_ROOT" >&2
  exit 1
fi
if [[ -z "$ACCOUNT_HOME" || ! -d "$ACCOUNT_HOME" || -L "$ACCOUNT_HOME" ]]; then
  /bin/echo "Account home must be a real directory: $ACCOUNT_HOME" >&2
  exit 1
fi

AUTOASSIST_ROOT="${AUTOASSIST_ROOT:A}"
ACCOUNT_HOME="${ACCOUNT_HOME:A}"
if [[ "$AUTOASSIST_ROOT" == "/" || "$AUTOASSIST_ROOT" == "$ACCOUNT_HOME" ]]; then
  /bin/echo "Refusing a broad AutoAssist root: $AUTOASSIST_ROOT" >&2
  exit 1
fi

PROJECTS_FILE="$AUTOASSIST_ROOT/PROJECTS.md"
STATUS_DIR="$AUTOASSIST_ROOT/01_PROJECTS/first-time"
STATUS_FILE="$STATUS_DIR/STATUS.md"
MARKER="$AUTOASSIST_ROOT/.install-state/first-time-complete"
VALIDATOR="$AUTOASSIST_ROOT/skills/first-time/scripts/validate-setup.sh"
PROGRESS_HELPER="$AUTOASSIST_ROOT/skills/first-time/scripts/walkthrough-progress.sh"

if [[ ! -f "$PROJECTS_FILE" || -L "$PROJECTS_FILE" ]]; then
  /bin/echo "PROJECTS.md must be a regular non-symlink file" >&2
  exit 1
fi
if [[ -e "$STATUS_DIR" && ( ! -d "$STATUS_DIR" || -L "$STATUS_DIR" ) ]]; then
  /bin/echo "First-time status directory must be a real directory" >&2
  exit 1
fi
if [[ -e "$STATUS_FILE" && ( ! -f "$STATUS_FILE" || -L "$STATUS_FILE" ) ]]; then
  /bin/echo "First-time status must be a regular non-symlink file" >&2
  exit 1
fi

if [[ "$STATE" == "pending" ]]; then
  if [[ -e "$MARKER" || -L "$MARKER" ]]; then
    /bin/echo "Refusing to report setup pending while the completion marker exists" >&2
    exit 1
  fi
  TARGET_HEADER="## Active"
  MANAGED_LINE="- [First-time setup](01_PROJECTS/first-time/STATUS.md): setup is incomplete; independent validation and the completion marker are pending."

  PENDING_CURRENT_STATUS="Setup is incomplete. Independent validation and .install-state/first-time-complete are pending."
  PENDING_NEXT_ACTION_1="Complete the local setup smoke objective."
  PENDING_NEXT_ACTION_2="Obtain independent read-only validation."
  PENDING_NEXT_ACTION_3="Write and validate the owner-only completion marker."
  PENDING_BLOCKERS="Independent validation and the completion marker remain pending."
  PENDING_REVIEW_READY=0
  if [[ -x "$PROGRESS_HELPER" && ! -L "$PROGRESS_HELPER" ]]; then
    progress_json="$("$PROGRESS_HELPER" --root "$AUTOASSIST_ROOT" --account-home "$ACCOUNT_HOME" show 2>/dev/null || true)"
    progress_smoke="$(/usr/bin/printf '%s\n' "$progress_json" | /usr/bin/sed -n 's/.*"smoke_objective_id":"\([a-z0-9][a-z0-9-]*\)".*/\1/p')"
    if [[ "$progress_json" == *'"status":"ready-for-review"'* \
      && "$progress_json" == *'"stage":"independent-review"'* \
      && "$progress_json" == *'"evidence":"local-smoke-readback"'* \
      && -n "$progress_smoke" && "$progress_smoke" != none ]]; then
      PENDING_CURRENT_STATUS="The local setup smoke is complete and its checkpoint is ready for independent read-only validation. The owner-only .install-state/first-time-complete marker remains pending."
      PENDING_NEXT_ACTION_1="Obtain independent read-only validation of the current configuration, doctor result, smoke objective $progress_smoke, file modes, and absence of secrets or raw messages."
      PENDING_NEXT_ACTION_2="After independent acceptance, write and validate the owner-only completion marker."
      PENDING_NEXT_ACTION_3="Read back both generated status surfaces, then resume the original task."
      PENDING_BLOCKERS="Independent read-only validation and the completion marker remain pending. Do not repeat the smoke unless checkpoint revalidation finds the recorded objective stale."
      PENDING_REVIEW_READY=1
    fi
  fi
else
  if [[ ! -x "$VALIDATOR" ]]; then
    /bin/echo "First-time setup validator is missing or not executable" >&2
    exit 1
  fi
  "$VALIDATOR" --root "$AUTOASSIST_ROOT" --account-home "$ACCOUNT_HOME" --require-marker >/dev/null
  TARGET_HEADER="## Completed"
  MANAGED_LINE="- [First-time setup](01_PROJECTS/first-time/STATUS.md): setup validation passed; the owner-only completion marker is present and current."
fi

target_header_count="$(/usr/bin/awk -v target="$TARGET_HEADER" '$0 == target { count += 1 } END { print count + 0 }' "$PROJECTS_FILE")"
legacy_entry_count="$(/usr/bin/awk 'index($0, "](01_PROJECTS/first-time/STATUS.md):") > 0 { count += 1 } END { print count + 0 }' "$PROJECTS_FILE")"
managed_start_count="$(/usr/bin/awk '$0 == "<!-- AUTOASSIST FIRST-TIME STATUS START -->" { count += 1 } END { print count + 0 }' "$PROJECTS_FILE")"
managed_end_count="$(/usr/bin/awk '$0 == "<!-- AUTOASSIST FIRST-TIME STATUS END -->" { count += 1 } END { print count + 0 }' "$PROJECTS_FILE")"
managed_structure_valid="$(/usr/bin/awk '
  BEGIN { in_managed_block = 0; invalid = 0 }
  $0 == "<!-- AUTOASSIST FIRST-TIME STATUS START -->" {
    if (in_managed_block) invalid = 1
    in_managed_block = 1
    next
  }
  $0 == "<!-- AUTOASSIST FIRST-TIME STATUS END -->" {
    if (!in_managed_block) invalid = 1
    in_managed_block = 0
    next
  }
  END {
    if (in_managed_block) invalid = 1
    print invalid ? 0 : 1
  }
' "$PROJECTS_FILE")"
if [[ "$target_header_count" != "1" ]]; then
  /bin/echo "PROJECTS.md must contain exactly one $TARGET_HEADER heading" >&2
  exit 1
fi
if [[ "$legacy_entry_count" -gt 1 || "$managed_start_count" -gt 1 || "$managed_end_count" -gt 1 \
  || "$managed_start_count" != "$managed_end_count" || "$managed_structure_valid" != "1" ]]; then
  /bin/echo "PROJECTS.md contains ambiguous first-time status entries" >&2
  exit 1
fi

cleanup() {
  if [[ -n "$PROJECTS_TEMP" && -f "$PROJECTS_TEMP" ]]; then /bin/rm -f -- "$PROJECTS_TEMP"; fi
  if [[ -n "$STATUS_TEMP" && -f "$STATUS_TEMP" ]]; then /bin/rm -f -- "$STATUS_TEMP"; fi
}
trap cleanup EXIT INT TERM

/bin/mkdir -p "$STATUS_DIR"
/bin/chmod 700 "$STATUS_DIR"
PROJECTS_TEMP="$(/usr/bin/mktemp "$PROJECTS_FILE.tmp.XXXXXX")"
STATUS_TEMP="$(/usr/bin/mktemp "$STATUS_FILE.tmp.XXXXXX")"

/usr/bin/awk -v target="$TARGET_HEADER" -v managed="$MANAGED_LINE" '
  BEGIN {
    in_old_block = 0
    in_target = 0
    skip_first_blank = 0
    inserted = 0
  }
  $0 == "<!-- AUTOASSIST FIRST-TIME STATUS START -->" {
    in_old_block = 1
    next
  }
  $0 == "<!-- AUTOASSIST FIRST-TIME STATUS END -->" {
    in_old_block = 0
    next
  }
  in_old_block { next }
  index($0, "](01_PROJECTS/first-time/STATUS.md):") > 0 { next }
  $0 == "No initiatives yet. Run the `first-time` skill to create the initial setup project, then copy `01_PROJECTS/_template` for each meaningful initiative." { next }
  $0 == target {
    print
    print ""
    print "<!-- AUTOASSIST FIRST-TIME STATUS START -->"
    print managed
    print "<!-- AUTOASSIST FIRST-TIME STATUS END -->"
    in_target = 1
    skip_first_blank = 1
    inserted = 1
    next
  }
  /^## / {
    in_target = 0
    skip_first_blank = 0
  }
  in_target && skip_first_blank && $0 == "" {
    skip_first_blank = 0
    next
  }
  in_target && $0 == "None." { next }
  {
    skip_first_blank = 0
    print
  }
  END {
    if (inserted != 1) exit 7
  }
' "$PROJECTS_FILE" > "$PROJECTS_TEMP"

if [[ "$STATE" == "pending" ]]; then
  /bin/cat > "$STATUS_TEMP" <<EOF
# First-time setup

## Objective

Configure and independently validate this AutoAssist installation without external mutation.

## Current status

$PENDING_CURRENT_STATUS

## Next actions

1. $PENDING_NEXT_ACTION_1
2. $PENDING_NEXT_ACTION_2
3. $PENDING_NEXT_ACTION_3

## Blockers

$PENDING_BLOCKERS

## Decisions needed

None.

## Completion gate

Independent validation must bind the current configuration and smoke objective, followed by a mode-600 marker and successful --require-marker readback.
EOF
else
  /bin/cat > "$STATUS_TEMP" <<'EOF'
# First-time setup

## Objective

Configure and independently validate this AutoAssist installation without external mutation.

## Current status

Setup validation passed. The owner-only `.install-state/first-time-complete` marker is present, current, and passed `--require-marker` readback.

## Next actions

None. AutoAssist may proceed with ordinary work under the configured privacy and permission boundaries.

## Blockers

None.

## Decisions needed

None.

## Completion gate

Passed through deterministic setup validation, an independently owned marker, and current marker-bound readback.
EOF
fi

projects_mode="$(/usr/bin/stat -f '%Lp' "$PROJECTS_FILE")"
status_mode="600"
if [[ -f "$STATUS_FILE" && ! -L "$STATUS_FILE" ]]; then
  status_mode="$(/usr/bin/stat -f '%Lp' "$STATUS_FILE")"
fi
/bin/chmod "$projects_mode" "$PROJECTS_TEMP"
/bin/chmod "$status_mode" "$STATUS_TEMP"
/bin/mv -f "$STATUS_TEMP" "$STATUS_FILE"
STATUS_TEMP=""
/bin/mv -f "$PROJECTS_TEMP" "$PROJECTS_FILE"
PROJECTS_TEMP=""

if [[ "$(/usr/bin/awk 'index($0, "](01_PROJECTS/first-time/STATUS.md):") > 0 { count += 1 } END { print count + 0 }' "$PROJECTS_FILE")" != "1" ]]; then
  /bin/echo "First-time command-center status readback is not unique" >&2
  exit 1
fi
if [[ "$STATE" == "pending" ]]; then
  /usr/bin/grep -F -q 'setup is incomplete' "$PROJECTS_FILE"
  if [[ "$PENDING_REVIEW_READY" == 1 ]]; then
    /usr/bin/grep -F -q 'The local setup smoke is complete' "$STATUS_FILE"
    /usr/bin/grep -F -q 'independent read-only validation' "$STATUS_FILE"
    /usr/bin/grep -F -q 'Do not repeat the smoke unless checkpoint revalidation finds the recorded objective stale.' "$STATUS_FILE"
    if /usr/bin/grep -F -q 'Complete the local setup smoke objective.' "$STATUS_FILE"; then
      /bin/echo "pending first-time status retained stale smoke-first language" >&2
      exit 1
    fi
  else
    /usr/bin/grep -F -q 'Setup is incomplete.' "$STATUS_FILE"
    /usr/bin/grep -F -q 'completion marker remain pending' "$STATUS_FILE"
  fi
else
  /usr/bin/grep -F -q 'setup validation passed' "$PROJECTS_FILE"
  /usr/bin/grep -F -q 'Setup validation passed.' "$STATUS_FILE"
  /usr/bin/grep -F -q 'completion marker is present and current' "$PROJECTS_FILE"
  if /usr/bin/grep -Eiq 'ready_for_validation|marker (is )?absent|validation (is )?pending' "$PROJECTS_FILE" "$STATUS_FILE"; then
    /bin/echo "Completed first-time status retained stale pending language" >&2
    exit 1
  fi
fi

/bin/echo "AutoAssist first-time status written: $STATE"
