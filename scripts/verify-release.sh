#!/bin/zsh

set -eu

ROOT="${1:-${0:A:h:h}}"
failures=0

pass() {
  /bin/echo "PASS  $1"
}

fail() {
  /bin/echo "FAIL  $1" >&2
  failures=$((failures + 1))
}

required_files=(
  AGENTS.md
  LICENSE
  PROJECTS.md
  README.md
  PRIVACY.md
  SECURITY.md
  VERSION
  Install.command
  install.sh
  uninstall.sh
  runtime/bin/autoassist
  runtime/lib/common.sh
  runtime/templates/io.autoassist.supervisor.plist.template
  scripts/privacy-scan.sh
  scripts/package.sh
  skills/first-time/SKILL.md
  skills/first-time/agents/openai.yaml
  skills/first-time/scripts/validate-setup.sh
  skills/first-time/scripts/write-status.sh
  docs/INSTALL.md
  docs/PERMISSIONS.md
  docs/COMPARISON.md
  docs/ARCHITECTURE.md
  docs/TROUBLESHOOTING.md
  tests/run-all.sh
  tests/test-first-time-status.sh
  tests/test-runtime.sh
  tests/test-install.sh
  tests/test-privacy-scan.sh
)

for relative in "${required_files[@]}"; do
  [[ -f "$ROOT/$relative" ]] && pass "required file $relative" || fail "required file $relative"
done

expected_mit_sha256="a8323253d2ae9e1eb82372f057ecb64f7f9892bcb2e53db758e7097e2da1270b"
actual_mit_sha256=""
if [[ -f "$ROOT/LICENSE" && ! -L "$ROOT/LICENSE" ]]; then
  actual_mit_sha256="$(/usr/bin/shasum -a 256 "$ROOT/LICENSE" | /usr/bin/awk '{print $1}')"
fi
if [[ "$actual_mit_sha256" == "$expected_mit_sha256" ]]; then
  pass "exact MIT license grant"
else
  fail "exact MIT license grant"
fi

release_license_count="$(/usr/bin/awk '$0 == "LICENSE" { count += 1 } END { print count + 0 }' "$ROOT/config/release-allowlist.txt")"
immutable_license_count="$(/usr/bin/awk '$0 == "LICENSE" { count += 1 } END { print count + 0 }' "$ROOT/config/immutable-manifest.txt")"
seed_license_count="$(/usr/bin/awk '$0 == "LICENSE" { count += 1 } END { print count + 0 }' "$ROOT/config/seed-manifest.txt")"

if [[ "$release_license_count" == "1" ]]; then
  pass "MIT license in release allowlist"
else
  fail "MIT license in release allowlist"
fi

if [[ "$immutable_license_count" == "1" ]]; then
  pass "MIT license in immutable manifest"
else
  fail "MIT license in immutable manifest"
fi

if [[ "$seed_license_count" == "0" ]]; then
  pass "MIT license excluded from user-owned seeds"
else
  fail "MIT license excluded from user-owned seeds"
fi

if /usr/bin/grep -F -q '[MIT License](LICENSE)' "$ROOT/README.md"; then
  pass "README MIT license discovery"
else
  fail "README MIT license discovery"
fi

executables=(
  Install.command
  install.sh
  uninstall.sh
  runtime/bin/autoassist
  scripts/privacy-scan.sh
  scripts/package.sh
  scripts/verify-release.sh
  skills/first-time/scripts/validate-setup.sh
  skills/first-time/scripts/write-status.sh
  tests/run-all.sh
  tests/test-first-time-status.sh
  tests/test-runtime.sh
  tests/test-install.sh
  tests/test-privacy-scan.sh
)

for relative in "${executables[@]}"; do
  [[ -x "$ROOT/$relative" ]] && pass "executable $relative" || fail "executable $relative"
done

shell_files=(
  Install.command
  install.sh
  uninstall.sh
  runtime/bin/autoassist
  runtime/lib/common.sh
  scripts/privacy-scan.sh
  scripts/package.sh
  scripts/verify-release.sh
  skills/first-time/scripts/validate-setup.sh
  skills/first-time/scripts/write-status.sh
  tests/run-all.sh
  tests/test-first-time-status.sh
  tests/test-runtime.sh
  tests/test-install.sh
  tests/test-privacy-scan.sh
)

for relative in "${shell_files[@]}"; do
  if [[ -f "$ROOT/$relative" ]] && /bin/zsh -n "$ROOT/$relative"; then
    pass "shell syntax $relative"
  else
    fail "shell syntax $relative"
  fi
done

if /usr/bin/plutil -lint "$ROOT/runtime/templates/io.autoassist.supervisor.plist.template" >/dev/null; then
  pass "LaunchAgent template"
else
  fail "LaunchAgent template"
fi

if /usr/bin/grep -q '^name: first-time$' "$ROOT/skills/first-time/SKILL.md" && \
   /usr/bin/grep -q '^description: .\{20,\}' "$ROOT/skills/first-time/SKILL.md"; then
  pass "first-time skill frontmatter"
else
  fail "first-time skill frontmatter"
fi

if LC_ALL=C /usr/bin/sort -c -u "$ROOT/config/release-allowlist.txt" 2>/dev/null; then
  pass "sorted unique release allowlist"
else
  fail "sorted unique release allowlist"
fi

VERIFY_TEMP="$(/usr/bin/mktemp -d -t autoassist-verify-release)"
trap '/bin/rm -rf "$VERIFY_TEMP"' EXIT INT TERM
VERIFY_ROOT="$VERIFY_TEMP/AutoAssist"
EXPECTED_PATHS="$VERIFY_TEMP/expected-paths.txt"
OBSERVED_PATHS="$VERIFY_TEMP/observed-paths.txt"
/bin/mkdir -p "$VERIFY_ROOT"
while IFS= read -r entry; do
  [[ -z "$entry" || "$entry" == \#* ]] && continue
  if [[ "$entry" == /* || "$entry" == *'..'* || "$entry" == *$'\n'* || ! -f "$ROOT/$entry" || -L "$ROOT/$entry" ]]; then
    fail "safe regular release entry"
    continue
  fi
  /bin/mkdir -p "$VERIFY_ROOT/${entry:h}"
  /bin/cp -p "$ROOT/$entry" "$VERIFY_ROOT/$entry"
  /usr/bin/printf '%s\n' "$entry" >> "$EXPECTED_PATHS"
done < "$ROOT/config/release-allowlist.txt"
LC_ALL=C /usr/bin/sort -u "$EXPECTED_PATHS" -o "$EXPECTED_PATHS"
(
  cd "$VERIFY_ROOT"
  /usr/bin/find . -type f -print | /usr/bin/sed 's|^\./||' | LC_ALL=C /usr/bin/sort > "$OBSERVED_PATHS"
)
if /usr/bin/cmp -s "$EXPECTED_PATHS" "$OBSERVED_PATHS"; then
  pass "exact release path set"
else
  fail "exact release path set"
fi

if "$VERIFY_ROOT/scripts/privacy-scan.sh" "$VERIFY_ROOT"; then
  pass "privacy scan of exact clean release tree"
else
  fail "privacy scan of exact clean release tree"
fi
trap - EXIT INT TERM
/bin/rm -rf "$VERIFY_TEMP"

if [[ "$failures" -gt 0 ]]; then
  /bin/echo "AutoAssist release verification failed with $failures check(s)." >&2
  exit 1
fi

/bin/echo "AutoAssist release verification passed."
