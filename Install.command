#!/bin/zsh

set -eu
SCRIPT_DIR="${0:A:h}"
exec /bin/zsh "$SCRIPT_DIR/install.sh" "$@"

