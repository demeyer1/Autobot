#!/bin/zsh
set -eu
umask 077
SOURCE_ROOT="${0:A:h:h}"
CURRENT_VERSION="$(/bin/cat "$SOURCE_ROOT/VERSION")"
[[ "$CURRENT_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { /bin/echo "candidate VERSION is invalid" >&2; exit 1; }
CURRENT_PATCH="${CURRENT_VERSION##*.}"
NEXT_PATCH=$((CURRENT_PATCH + 1))
NEXT_VERSION_VALUE="${CURRENT_VERSION%.*}.$NEXT_PATCH"
LEGACY_ZIP="${AUTOASSIST_LEGACY_ZIP:-}"
[[ -n "$LEGACY_ZIP" && "$LEGACY_ZIP" == /* && -f "$LEGACY_ZIP" && ! -L "$LEGACY_ZIP" ]] || { /bin/echo "AUTOASSIST_LEGACY_ZIP must name exact public v0.1.0 ZIP" >&2; exit 2; }
[[ "$(/usr/bin/shasum -a 256 "$LEGACY_ZIP" | /usr/bin/awk '{print $1}')" == bdd1985cb7a3494d2df32cb0c03e971dec6fd87bee476e1f475f0c4a6f78ef3b ]] || { /bin/echo "legacy ZIP hash mismatch" >&2; exit 1; }
TEMP_PARENT="${TMPDIR:-/tmp}"; TEMP_PARENT="${TEMP_PARENT%/}"
TEST_ROOT="$(/usr/bin/mktemp -d "$TEMP_PARENT/autoassist-install-upgrade.XXXXXX")"
TEST_ROOT="${TEST_ROOT:A}"
ACCOUNT_HOME="$TEST_ROOT/Legacy User"
DESTINATION="$ACCOUNT_HOME/AutoAssist"
cleanup() { local s=$?; [[ -d "$TEST_ROOT" ]] && /bin/rm -rf "$TEST_ROOT"; return "$s"; }
trap cleanup EXIT INT TERM
/bin/mkdir -p "$ACCOUNT_HOME" "$TEST_ROOT/extracted"
/usr/bin/unzip -q "$LEGACY_ZIP" -d "$TEST_ROOT/extracted"
LEGACY_SOURCE="$TEST_ROOT/extracted/AutoAssist"
[[ -x "$LEGACY_SOURCE/install.sh" ]] || /bin/chmod +x "$LEGACY_SOURCE/install.sh"
"$LEGACY_SOURCE/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --skip-launch-agent > "$TEST_ROOT/legacy-install.log"
/usr/bin/printf '\nuser seed survives\n' >> "$DESTINATION/PROJECTS.md"
seed_hash="$(/usr/bin/shasum -a 256 "$DESTINATION/PROJECTS.md" | /usr/bin/awk '{print $1}')"
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id legacyfixture --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/upgrade.log"
[[ "$(/bin/cat "$DESTINATION/VERSION")" == "$CURRENT_VERSION" && "$seed_hash" == "$(/usr/bin/shasum -a 256 "$DESTINATION/PROJECTS.md" | /usr/bin/awk '{print $1}')" ]]
[[ -f "$DESTINATION/.install-state/receipt.json" && -f "$DESTINATION/.install-state/installed-manifest.sha256" ]]
[[ ! -e "$ACCOUNT_HOME/Library/LaunchAgents/io.autoassist.supervisor.plist" ]] || { /bin/echo "skip-launch update orphaned the legacy plist" >&2; exit 1; }
/usr/bin/grep -F -q '"service_label":""' "$DESTINATION/.install-state/receipt.json"
before_legacy_rollback="$(/usr/bin/shasum -a 256 "$DESTINATION/VERSION" | /usr/bin/awk '{print $1}')"
if "$DESTINATION/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --rollback --skip-launch-agent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/legacy-rollback.log" 2>&1; then /bin/echo "schema-incompatible legacy rollback was accepted" >&2; exit 1; fi
[[ "$before_legacy_rollback" == "$(/usr/bin/shasum -a 256 "$DESTINATION/VERSION" | /usr/bin/awk '{print $1}')" ]]

NEXT_VERSION_ROOT="$TEST_ROOT/release-$NEXT_VERSION_VALUE"
/bin/cp -Rp "$SOURCE_ROOT" "$NEXT_VERSION_ROOT"
/usr/bin/printf '%s\n' "$NEXT_VERSION_VALUE" > "$NEXT_VERSION_ROOT/VERSION"
AUTOASSIST_TEST_NODE_ABSENT=1 "$NEXT_VERSION_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id legacyfixture --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/next-version.log"
[[ "$(/bin/cat "$DESTINATION/VERSION")" == "$NEXT_VERSION_VALUE" ]]
"$DESTINATION/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --rollback --skip-launch-agent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/rollback.log"
[[ "$(/bin/cat "$DESTINATION/VERSION")" == "$CURRENT_VERSION" && "$seed_hash" == "$(/usr/bin/shasum -a 256 "$DESTINATION/PROJECTS.md" | /usr/bin/awk '{print $1}')" ]] || { /bin/echo "schema-compatible rollback did not preserve current seed state" >&2; exit 1; }
/usr/bin/printf '\nuser README customization\n' >> "$DESTINATION/README.md"
before="$(/usr/bin/shasum -a 256 "$DESTINATION/README.md" | /usr/bin/awk '{print $1}')"
AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id legacyfixture --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/reinstall-same-release.log"
[[ "$before" == "$(/usr/bin/shasum -a 256 "$DESTINATION/README.md" | /usr/bin/awk '{print $1}')" ]] || { /bin/echo "same-release reinstall did not preserve customization" >&2; exit 1; }
upstream_readme_hash="$(/usr/bin/shasum -a 256 "$SOURCE_ROOT/README.md" | /usr/bin/awk '{print $1}')"
baseline_readme_hash="$(/usr/bin/awk '$2 == "README.md" { print $1; exit }' "$DESTINATION/.install-state/installed-manifest.sha256")"
[[ "$baseline_readme_hash" == "$upstream_readme_hash" && "$baseline_readme_hash" != "$before" ]] || { /bin/echo "same-release reinstall blessed customized bytes as upstream baseline" >&2; exit 1; }
NEXT_RELEASE="$TEST_ROOT/release-next"
/bin/cp -Rp "$SOURCE_ROOT" "$NEXT_RELEASE"
/usr/bin/printf '\nnext release README change\n' >> "$NEXT_RELEASE/README.md"
if AUTOASSIST_TEST_NODE_ABSENT=1 "$NEXT_RELEASE/install.sh" --home-root "$ACCOUNT_HOME" --destination "$DESTINATION" --instance-id legacyfixture --skip-launch-agent --target-quiescent --test-mode --test-root "$TEST_ROOT" > "$TEST_ROOT/conflict.log" 2>&1; then /bin/echo "three-way conflict was not rejected" >&2; exit 1; fi
[[ "$before" == "$(/usr/bin/shasum -a 256 "$DESTINATION/README.md" | /usr/bin/awk '{print $1}')" && ! -e "$DESTINATION/.install-state/migration.lock" ]]
/bin/echo "Exact public v0.1.0 upgrade, pristine-baseline chaining, schema-safe rollback, seed preservation, and three-way conflict protection passed."
