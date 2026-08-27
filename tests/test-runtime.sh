#!/bin/zsh

set -eu

SOURCE_ROOT="${0:A:h:h}"
TEST_ROOT="$(/usr/bin/mktemp -d -t autoassist-runtime-test)"
trap '/bin/rm -rf "$TEST_ROOT"' EXIT INT TERM
RUNTIME_ROOT="$TEST_ROOT/AutoAssist"
/bin/mkdir -p "$RUNTIME_ROOT"
while IFS= read -r entry || [[ -n "$entry" ]]; do
  [[ -z "$entry" || "$entry" == \#* ]] && continue
  if [[ "$entry" == /* || "$entry" == *'..'* || "$entry" == *$'\n'* ]]; then
    /bin/echo "unsafe runtime fixture allowlist entry" >&2
    exit 1
  fi
  if [[ ! -f "$SOURCE_ROOT/$entry" || -L "$SOURCE_ROOT/$entry" ]]; then
    /bin/echo "runtime fixture allowlist entry is not a regular file" >&2
    exit 1
  fi
  /bin/mkdir -p "$RUNTIME_ROOT/${entry:h}"
  /bin/cp -p "$SOURCE_ROOT/$entry" "$RUNTIME_ROOT/$entry"
done < "$SOURCE_ROOT/config/release-allowlist.txt"
/bin/chmod +x "$RUNTIME_ROOT/runtime/bin/autoassist" "$RUNTIME_ROOT/runtime/lib/common.sh" "$RUNTIME_ROOT/scripts/privacy-scan.sh"

CLI="$RUNTIME_ROOT/runtime/bin/autoassist"
"$CLI" initialize-zones >/dev/null
"$CLI" objective-create test-objective "Test objective" >/dev/null

stages=(research_complete draft_complete destination_updated save_confirmed rendered_readback_verified)
counter=0
for stage in "${stages[@]}"; do
  counter=$((counter + 1))
  evidence="$TEST_ROOT/evidence-$counter.txt"
  /usr/bin/printf 'stage=%s\nsequence=%s\n' "$stage" "$counter" > "$evidence"
  "$CLI" checkpoint test-objective "$stage" "$evidence" worker-one >/dev/null
  if "$CLI" validate-stage test-objective "$stage" worker-one >/dev/null 2>&1; then
    /bin/echo "same-label validation unexpectedly passed" >&2
    exit 1
  fi
  if [[ -e "$RUNTIME_ROOT/state/objectives/test-objective/.lock" ]]; then
    /bin/echo "same-label rejection left the objective lock behind" >&2
    exit 1
  fi
  "$CLI" validate-stage test-objective "$stage" validator-two >/dev/null
done

if [[ "$(<"$RUNTIME_ROOT/state/objectives/test-objective/state")" != "complete" ]]; then
  /bin/echo "objective did not reach complete after five independent validations" >&2
  exit 1
fi

"$CLI" objective-create tamper-objective "Tamper objective" >/dev/null
tamper_source="$TEST_ROOT/tamper.txt"
/usr/bin/printf 'original\n' > "$tamper_source"
"$CLI" checkpoint tamper-objective research_complete "$tamper_source" worker-one >/dev/null
/usr/bin/printf 'changed\n' > "$RUNTIME_ROOT/state/objectives/tamper-objective/evidence/research_complete/evidence.bin"
if "$CLI" validate-stage tamper-objective research_complete validator-two >/dev/null 2>&1; then
  /bin/echo "tampered evidence unexpectedly validated" >&2
  exit 1
fi

"$CLI" objective-create stalled-objective "Stalled objective" >/dev/null
/usr/bin/printf '0\n' > "$RUNTIME_ROOT/state/objectives/stalled-objective/last_progress_epoch"
"$CLI" supervisor-tick >/dev/null
if [[ ! -f "$RUNTIME_ROOT/state/objectives/stalled-objective/recovery_needed" ]]; then
  /bin/echo "stalled objective was not flagged for recovery" >&2
  exit 1
fi

/bin/echo "Runtime tests passed."
