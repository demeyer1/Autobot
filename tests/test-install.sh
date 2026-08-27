#!/bin/zsh

set -eu

SOURCE_ROOT="${0:A:h:h}"
TEST_ROOT="$(/usr/bin/mktemp -d -t autoassist-install-test)"
trap '/bin/rm -rf "$TEST_ROOT"' EXIT INT TERM
TEST_HOME="$TEST_ROOT/home"
DESTINATION="$TEST_HOME/AutoAssist"
/bin/mkdir -p "$TEST_HOME"

HELP_OUTPUT="$("$SOURCE_ROOT/install.sh" --help)"
if ! /usr/bin/grep -q -- '--home-root PATH' <<< "$HELP_OUTPUT"; then
  /bin/echo "installer help omitted the isolated home-root option" >&2
  exit 1
fi
if /usr/bin/grep -q -- '--non-interactive' <<< "$HELP_OUTPUT"; then
  /bin/echo "installer help retained the removed no-op option" >&2
  exit 1
fi

UNKNOWN_HOME="$TEST_ROOT/unknown-option-home"
/bin/mkdir -p "$UNKNOWN_HOME"
if HOME="$UNKNOWN_HOME" "$SOURCE_ROOT/install.sh" --non-interactive >/dev/null 2>&1; then
  /bin/echo "installer accepted the removed no-op option" >&2
  exit 1
fi
if [[ -e "$UNKNOWN_HOME/AutoAssist" || -e "$UNKNOWN_HOME/.codex" || -e "$UNKNOWN_HOME/Library" ]]; then
  /bin/echo "unknown-option rejection occurred after installation mutation" >&2
  exit 1
fi

DEFAULT_HOME="$TEST_ROOT/default-home"
/bin/mkdir -p "$DEFAULT_HOME"
"$SOURCE_ROOT/install.sh" --home-root "$DEFAULT_HOME" --skip-launch-agent >/dev/null
if [[ ! -f "$DEFAULT_HOME/AutoAssist/.install-state/managed-by-autoassist" ]]; then
  /bin/echo "isolated home root did not default destination to its AutoAssist child" >&2
  exit 1
fi
AUTOASSIST_ACCOUNT_HOME="$DEFAULT_HOME" "$DEFAULT_HOME/AutoAssist/runtime/bin/autoassist" doctor --quiet

SPACE_HOME="$TEST_ROOT/space home"
SPACE_DESTINATION="$SPACE_HOME/AutoAssist Project"
/bin/mkdir -p "$SPACE_HOME"
"$SOURCE_ROOT/install.sh" --home-root "$SPACE_HOME" --destination "$SPACE_DESTINATION" --skip-launch-agent >/dev/null
if [[ ! -f "$SPACE_DESTINATION/.install-state/managed-by-autoassist" ]]; then
  /bin/echo "installer did not support a safe destination containing spaces" >&2
  exit 1
fi
if ! /usr/bin/plutil -lint "$SPACE_HOME/Library/LaunchAgents/io.autoassist.supervisor.plist" >/dev/null; then
  /bin/echo "space-path LaunchAgent definition is invalid" >&2
  exit 1
fi

AMPERSAND_HOME="$TEST_ROOT/ampersand&home"
AMPERSAND_DESTINATION="$AMPERSAND_HOME/AutoAssist"
/bin/mkdir -p "$AMPERSAND_HOME"
if "$SOURCE_ROOT/install.sh" --home-root "$AMPERSAND_HOME" --destination "$AMPERSAND_DESTINATION" --skip-launch-agent >/dev/null 2>&1; then
  /bin/echo "installer accepted an XML-unsafe destination" >&2
  exit 1
fi
if [[ -e "$AMPERSAND_DESTINATION" || -e "$AMPERSAND_HOME/.codex" || -e "$AMPERSAND_HOME/Library" ]]; then
  /bin/echo "XML-unsafe path rejection occurred after installation mutation" >&2
  exit 1
fi

CONFLICT_HOME="$TEST_ROOT/conflict-home"
CONFLICT_DESTINATION="$CONFLICT_HOME/AutoAssist"
/bin/mkdir -p "$CONFLICT_HOME/.codex/skills/first-time"
/usr/bin/printf 'user-owned skill\n' > "$CONFLICT_HOME/.codex/skills/first-time/SKILL.md"
if "$SOURCE_ROOT/install.sh" --home-root "$CONFLICT_HOME" --destination "$CONFLICT_DESTINATION" --skip-launch-agent >/dev/null 2>&1; then
  /bin/echo "installer overwrote a non-AutoAssist first-time skill" >&2
  exit 1
fi
if [[ -e "$CONFLICT_DESTINATION" ]]; then
  /bin/echo "skill-conflict preflight left a partial destination" >&2
  exit 1
fi
if [[ "$(/bin/cat "$CONFLICT_HOME/.codex/skills/first-time/SKILL.md")" != "user-owned skill" ]]; then
  /bin/echo "skill-conflict preflight changed the user-owned skill" >&2
  exit 1
fi

UNMANAGED_HOME="$TEST_ROOT/unmanaged-home"
UNMANAGED_DESTINATION="$UNMANAGED_HOME/AutoAssist"
/bin/mkdir -p "$UNMANAGED_DESTINATION"
/usr/bin/printf 'unmanaged sentinel\n' > "$UNMANAGED_DESTINATION/sentinel.txt"
if "$SOURCE_ROOT/install.sh" --home-root "$UNMANAGED_HOME" --destination "$UNMANAGED_DESTINATION" --skip-launch-agent >/dev/null 2>&1; then
  /bin/echo "installer overwrote an unmanaged destination" >&2
  exit 1
fi
if [[ "$(/bin/cat "$UNMANAGED_DESTINATION/sentinel.txt")" != "unmanaged sentinel" ]]; then
  /bin/echo "unmanaged-destination preflight changed existing content" >&2
  exit 1
fi

start_epoch="$(/bin/date +%s)"
"$SOURCE_ROOT/install.sh" --home-root "$TEST_HOME" --destination "$DESTINATION" --skip-launch-agent >/dev/null
end_epoch="$(/bin/date +%s)"
duration="$((end_epoch - start_epoch))"
if [[ "$duration" -ge 1800 ]]; then
  /bin/echo "fresh install exceeded 30 minutes: ${duration}s" >&2
  exit 1
fi

required=(
  "$DESTINATION/AGENTS.md"
  "$DESTINATION/LICENSE"
  "$DESTINATION/state"
  "$DESTINATION/00_CONTEXT/PRIVATE/INDEX.md"
  "$TEST_HOME/.codex/skills/first-time/SKILL.md"
  "$TEST_HOME/Library/LaunchAgents/io.autoassist.supervisor.plist"
)
for path in "${required[@]}"; do
  if [[ ! -e "$path" ]]; then
    /bin/echo "fresh install is missing $path" >&2
    exit 1
  fi
done

source_license_hash="$(/usr/bin/shasum -a 256 "$SOURCE_ROOT/LICENSE" | /usr/bin/awk '{print $1}')"
installed_license_hash="$(/usr/bin/shasum -a 256 "$DESTINATION/LICENSE" | /usr/bin/awk '{print $1}')"
if [[ "$source_license_hash" != "$installed_license_hash" ]]; then
  /bin/echo "fresh install did not copy the exact MIT license" >&2
  exit 1
fi

AUTOASSIST_ACCOUNT_HOME="$TEST_HOME" "$DESTINATION/runtime/bin/autoassist" doctor --quiet

for zone in PRIVATE FAMILY_FRIENDS WORK SHARED; do
  zone_index="$DESTINATION/00_CONTEXT/$zone/INDEX.md"
  if /usr/bin/grep -F -q '\n' "$zone_index"; then
    /bin/echo "zone index contains a literal backslash-n sequence: $zone" >&2
    exit 1
  fi
  if [[ "$(/usr/bin/wc -l < "$zone_index")" -lt 3 ]]; then
    /bin/echo "zone index does not contain real Markdown line breaks: $zone" >&2
    exit 1
  fi
done

/bin/mkdir -p "$DESTINATION/01_PROJECTS/user-project"
/usr/bin/printf 'private sentinel\n' > "$DESTINATION/00_CONTEXT/PRIVATE/sentinel.txt"
/usr/bin/printf 'project sentinel\n' > "$DESTINATION/01_PROJECTS/user-project/STATUS.md"
/usr/bin/printf 'output sentinel\n' > "$DESTINATION/03_OUTPUTS/sentinel.txt"
/usr/bin/printf 'event sentinel\n' > "$DESTINATION/state/events/sentinel.txt"
/usr/bin/printf 'profile sentinel\n' > "$DESTINATION/config/profile.conf"
/usr/bin/printf '{"version":1,"updated_at":"sentinel","issues":[]}\n' > "$DESTINATION/00_CONTEXT/ISSUES/issues.json"
/usr/bin/printf 'projects sentinel\n' > "$DESTINATION/PROJECTS.md"
/usr/bin/printf 'memory sentinel\n' > "$DESTINATION/00_CONTEXT/MEMORY.md"

SCAN_STDOUT="$TEST_ROOT/installed-privacy-scan.stdout"
SCAN_STDERR="$TEST_ROOT/installed-privacy-scan.stderr"
if "$DESTINATION/runtime/bin/autoassist" privacy-scan >"$SCAN_STDOUT" 2>"$SCAN_STDERR"; then
  /bin/echo "configured-workspace privacy scan unexpectedly ran" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'release-candidate check' "$SCAN_STDERR"; then
  /bin/echo "configured-workspace privacy scan did not explain its fail-closed boundary" >&2
  exit 1
fi
if /usr/bin/grep -q 'private sentinel' "$SCAN_STDOUT" "$SCAN_STDERR"; then
  /bin/echo "configured-workspace privacy scan exposed user content" >&2
  exit 1
fi

sentinels=(
  00_CONTEXT/PRIVATE/sentinel.txt
  01_PROJECTS/user-project/STATUS.md
  03_OUTPUTS/sentinel.txt
  state/events/sentinel.txt
  config/profile.conf
  00_CONTEXT/ISSUES/issues.json
  PROJECTS.md
  00_CONTEXT/MEMORY.md
)

HASH_FILE="$TEST_ROOT/sentinel-hashes.before"
for relative in "${sentinels[@]}"; do
  /usr/bin/shasum -a 256 "$DESTINATION/$relative" >> "$HASH_FILE"
done

/usr/bin/printf 'mutated immutable runtime\n' > "$DESTINATION/runtime/bin/autoassist"
/usr/bin/printf 'mutated license\n' > "$DESTINATION/LICENSE"
"$SOURCE_ROOT/install.sh" --home-root "$TEST_HOME" --destination "$DESTINATION" --skip-launch-agent >/dev/null

for relative in "${sentinels[@]}"; do
  expected="$(/usr/bin/grep "  $DESTINATION/$relative$" "$HASH_FILE" | /usr/bin/awk '{print $1}')"
  actual="$(/usr/bin/shasum -a 256 "$DESTINATION/$relative" | /usr/bin/awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    /bin/echo "reinstall changed user-owned file: $relative" >&2
    exit 1
  fi
done

source_runtime_hash="$(/usr/bin/shasum -a 256 "$SOURCE_ROOT/runtime/bin/autoassist" | /usr/bin/awk '{print $1}')"
installed_runtime_hash="$(/usr/bin/shasum -a 256 "$DESTINATION/runtime/bin/autoassist" | /usr/bin/awk '{print $1}')"
if [[ "$source_runtime_hash" != "$installed_runtime_hash" ]]; then
  /bin/echo "reinstall did not refresh immutable runtime" >&2
  exit 1
fi

installed_license_hash="$(/usr/bin/shasum -a 256 "$DESTINATION/LICENSE" | /usr/bin/awk '{print $1}')"
if [[ "$source_license_hash" != "$installed_license_hash" ]]; then
  /bin/echo "reinstall did not restore the exact MIT license" >&2
  exit 1
fi

/bin/echo "Install and reinstall tests passed in ${duration}s."
