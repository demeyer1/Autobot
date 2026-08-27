#!/bin/zsh

set -eu

TARGET="${1:-${HOME}/AutoAssist}"
TARGET="${TARGET:A}"

if [[ "$TARGET" == "/" || "$TARGET" == "${HOME:A}" || ! -f "$TARGET/.install-state/managed-by-autoassist" ]]; then
  /bin/echo "Refusing to uninstall an unverified or broad target: $TARGET" >&2
  exit 2
fi

GUI_DOMAIN="gui/$(/usr/bin/id -u)"
/bin/launchctl bootout "$GUI_DOMAIN/io.autoassist.supervisor" >/dev/null 2>&1 || true

TRASH_TARGET="${HOME}/.Trash/AutoAssist-uninstalled-$(/bin/date +%Y%m%d-%H%M%S)"
/bin/mv "$TARGET" "$TRASH_TARGET"
/bin/echo "Moved the managed AutoAssist install to $TRASH_TARGET. It can be restored from Trash."

