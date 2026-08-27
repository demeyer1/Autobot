#!/bin/zsh

set -eu

SOURCE_ROOT="${0:A:h}"
ACCOUNT_HOME="${HOME}"
DESTINATION=""
DESTINATION_EXPLICIT=0
SKIP_LAUNCH_AGENT=0

usage() {
  /bin/cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --destination PATH     Install into PATH. Default: ~/AutoAssist
  --home-root PATH       Use PATH for user-scoped files. Intended for tests.
  --skip-launch-agent    Do not load the local liveness supervisor.
  --help                 Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination) DESTINATION="${2:-}"; DESTINATION_EXPLICIT=1; shift 2 ;;
    --home-root) ACCOUNT_HOME="${2:-}"; shift 2 ;;
    --skip-launch-agent) SKIP_LAUNCH_AGENT=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) /bin/echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$DESTINATION_EXPLICIT" -eq 0 && -n "$ACCOUNT_HOME" ]]; then
  DESTINATION="$ACCOUNT_HOME/AutoAssist"
fi

if [[ -z "$DESTINATION" || -z "$ACCOUNT_HOME" ]]; then
  /bin/echo "Destination and home root must be non-empty." >&2
  exit 2
fi

ACCOUNT_HOME="${ACCOUNT_HOME:A}"
DESTINATION="${DESTINATION:A}"
SOURCE_ROOT="${SOURCE_ROOT:A}"
SKILL_DESTINATION="$ACCOUNT_HOME/.codex/skills/first-time"

if [[ "$DESTINATION" == "/" || "$DESTINATION" == "$ACCOUNT_HOME" ]]; then
  /bin/echo "Refusing to install into a broad filesystem or home root." >&2
  exit 2
fi

if [[ ! "$DESTINATION" =~ '^[A-Za-z0-9._/ -]+$' ]]; then
  /bin/echo "Destination may contain only letters, digits, spaces, periods, underscores, hyphens, and slashes." >&2
  exit 2
fi

case "$DESTINATION" in
  "$ACCOUNT_HOME"/*) ;;
  *) /bin/echo "Destination must be a child of the selected home root." >&2; exit 2 ;;
esac

if [[ ! -f "$SOURCE_ROOT/AGENTS.md" || ! -f "$SOURCE_ROOT/config/release-allowlist.txt" ]]; then
  /bin/echo "This is not a complete AutoAssist release." >&2
  exit 2
fi

if [[ -e "$SKILL_DESTINATION" && ! -f "$SKILL_DESTINATION/.autoassist-skill" ]]; then
  /bin/echo "A non-AutoAssist first-time skill already exists at $SKILL_DESTINATION" >&2
  /bin/echo "Move or rename it, then rerun the installer." >&2
  exit 5
fi

START_EPOCH="$(/bin/date +%s)"
/bin/echo "Installing AutoAssist into $DESTINATION"

INSTALL_MODE="fresh"
if [[ -f "$DESTINATION/.install-state/managed-by-autoassist" ]]; then
  INSTALL_MODE="update"
fi

copy_replace() {
  local entry="$1"
  local source_path="$SOURCE_ROOT/$entry"
  local destination_path="$DESTINATION/$entry"
  if [[ "$entry" == /* || "$entry" == *'..'* || "$entry" == *$'\n'* ]]; then
    /bin/echo "Unsafe release manifest entry: $entry" >&2
    exit 4
  fi
  if [[ ! -e "$source_path" || -L "$source_path" ]]; then
    /bin/echo "Release manifest entry is missing: $entry" >&2
    exit 4
  fi
  /bin/mkdir -p "${destination_path:h}"
  /bin/rm -rf "$destination_path"
  /bin/cp -R "$source_path" "$destination_path"
}

copy_if_missing() {
  local entry="$1"
  local source_path="$SOURCE_ROOT/$entry"
  local destination_path="$DESTINATION/$entry"
  if [[ "$entry" == /* || "$entry" == *'..'* || "$entry" == *$'\n'* ]]; then
    /bin/echo "Unsafe seed manifest entry: $entry" >&2
    exit 4
  fi
  if [[ ! -e "$source_path" || -L "$source_path" ]]; then
    /bin/echo "Seed manifest entry is missing: $entry" >&2
    exit 4
  fi
  if [[ ! -e "$destination_path" ]]; then
    /bin/mkdir -p "${destination_path:h}"
    /bin/cp -R "$source_path" "$destination_path"
  fi
}

if [[ "$SOURCE_ROOT" != "$DESTINATION" ]]; then
  if [[ -e "$DESTINATION" && ! -f "$DESTINATION/.install-state/managed-by-autoassist" ]]; then
    /bin/echo "Destination exists and is not a managed AutoAssist install: $DESTINATION" >&2
    exit 3
  fi
  /bin/mkdir -p "$DESTINATION"
  if [[ "$INSTALL_MODE" == "fresh" ]]; then
    while IFS= read -r entry; do
      [[ -z "$entry" || "$entry" == \#* ]] && continue
      copy_replace "$entry"
    done < "$SOURCE_ROOT/config/release-allowlist.txt"
  else
    while IFS= read -r entry; do
      [[ -z "$entry" || "$entry" == \#* ]] && continue
      copy_replace "$entry"
    done < "$SOURCE_ROOT/config/immutable-manifest.txt"
    while IFS= read -r entry; do
      [[ -z "$entry" || "$entry" == \#* ]] && continue
      copy_if_missing "$entry"
    done < "$SOURCE_ROOT/config/seed-manifest.txt"
  fi
fi

/bin/chmod +x "$DESTINATION/Install.command" "$DESTINATION/install.sh" "$DESTINATION/uninstall.sh"
/bin/chmod +x "$DESTINATION/runtime/bin/autoassist" "$DESTINATION/runtime/lib/common.sh"
/bin/chmod +x "$DESTINATION/scripts/privacy-scan.sh" "$DESTINATION/scripts/package.sh" "$DESTINATION/scripts/verify-release.sh"
/bin/chmod +x "$DESTINATION/tests/run-all.sh" "$DESTINATION/tests/test-runtime.sh" "$DESTINATION/tests/test-install.sh" "$DESTINATION/tests/test-first-time-status.sh"
/bin/chmod +x "$DESTINATION/skills/first-time/scripts/validate-setup.sh" "$DESTINATION/skills/first-time/scripts/write-status.sh"

/bin/mkdir -p "$DESTINATION/.install-state"
/bin/chmod 700 "$DESTINATION/.install-state"
/usr/bin/printf '%s\n' "managed-by=AutoAssist" > "$DESTINATION/.install-state/managed-by-autoassist"
/bin/chmod 600 "$DESTINATION/.install-state/managed-by-autoassist"

if [[ ! -f "$DESTINATION/config/profile.conf" ]]; then
  /bin/cp "$DESTINATION/config/profile.example.conf" "$DESTINATION/config/profile.conf"
  /bin/chmod 600 "$DESTINATION/config/profile.conf"
fi

AUTOASSIST_HOME="$DESTINATION" "$DESTINATION/runtime/bin/autoassist" initialize-zones >/dev/null

/bin/mkdir -p "$ACCOUNT_HOME/.codex/skills"
/bin/rm -rf "$SKILL_DESTINATION"
/bin/cp -R "$DESTINATION/skills/first-time" "$SKILL_DESTINATION"
INSTALLED_VERSION="$(/bin/cat "$DESTINATION/VERSION")"
/usr/bin/printf '%s\n' "AutoAssist $INSTALLED_VERSION" > "$SKILL_DESTINATION/.autoassist-skill"
/bin/chmod -R go-rwx "$SKILL_DESTINATION"

LAUNCH_AGENT_DIR="$ACCOUNT_HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENT_DIR/io.autoassist.supervisor.plist"
/bin/mkdir -p "$LAUNCH_AGENT_DIR"
/usr/bin/sed "s|__AUTOASSIST_HOME__|$DESTINATION|g" "$DESTINATION/runtime/templates/io.autoassist.supervisor.plist.template" > "$PLIST_PATH"
/bin/chmod 600 "$PLIST_PATH"
/usr/bin/plutil -lint "$PLIST_PATH" >/dev/null

if [[ "$SKIP_LAUNCH_AGENT" -eq 0 ]]; then
  GUI_DOMAIN="gui/$(/usr/bin/id -u)"
  /bin/launchctl bootout "$GUI_DOMAIN/io.autoassist.supervisor" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap "$GUI_DOMAIN" "$PLIST_PATH"
  /bin/launchctl kickstart -k "$GUI_DOMAIN/io.autoassist.supervisor"
  AUTOASSIST_ACCOUNT_HOME="$ACCOUNT_HOME" "$DESTINATION/runtime/bin/autoassist" doctor --quiet
fi

END_EPOCH="$(/bin/date +%s)"
DURATION="$((END_EPOCH - START_EPOCH))"
/usr/bin/printf 'version=%s\ninstalled_at=%s\nduration_seconds=%s\npath=%s\n' \
  "$INSTALLED_VERSION" "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$DURATION" "$DESTINATION" \
  > "$DESTINATION/.install-state/receipt.txt"
/bin/chmod 600 "$DESTINATION/.install-state/receipt.txt"

/bin/echo "AutoAssist installed in ${DURATION}s."
/bin/echo "Next: open this folder as a new ChatGPT Project and run the first-time skill."
