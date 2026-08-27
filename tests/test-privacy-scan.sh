#!/bin/zsh

emulate -LR zsh
set -eu
setopt pipe_fail
export LC_ALL=C
export LANG=C
export TZ=UTC

ROOT="${0:A:h:h}"
SCANNER="$ROOT/scripts/privacy-scan.sh"
TEST_TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/autoassist-privacy-test.XXXXXX")"
cleanup() {
  /bin/rm -rf -- "$TEST_TEMP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

integer assertions=0
integer case_sequence=0

pass() {
  assertions=$((assertions + 1))
  /usr/bin/printf 'PASS  %s\n' "$1"
}

fail() {
  /usr/bin/printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

new_case() {
  case_sequence=$((case_sequence + 1))
  REPLY="$TEST_TEMP/case-$case_sequence"
  /bin/mkdir -p "$REPLY"
}

expect_clean() {
  local label="$1"
  local directory="$2"
  local output
  if ! output="$($SCANNER "$directory" 2>&1)"; then
    /usr/bin/printf '%s\n' "$output" >&2
    fail "$label"
  fi
  [[ "$output" == *'findings=0'* ]] || fail "$label did not report a zero-finding attestation"
  pass "$label"
}

expect_rejection() {
  local label="$1"
  local directory="$2"
  local expected_rule="$3"
  local sentinel="${4:-}"
  local expected_file_id="${5:-}"
  local output

  if output="$($SCANNER "$directory" 2>&1)"; then
    fail "$label was accepted"
  fi
  [[ "$output" == *"rule=$expected_rule "* ]] || {
    /usr/bin/printf '%s\n' "$output" >&2
    fail "$label did not report the expected rule"
  }
  [[ "$output" != *"$directory"* ]] || fail "$label disclosed its fixture path"
  if [[ -n "$sentinel" ]]; then
    [[ "$output" != *"$sentinel"* ]] || fail "$label disclosed the matched value"
  fi
  if [[ -n "$expected_file_id" ]]; then
    [[ "$output" == *"file=$expected_file_id "* ]] || fail "$label did not report its deterministic safe file mapping"
  fi
  [[ "$output" == *'value=[REDACTED]'* ]] || fail "$label did not redact its finding"
  pass "$label"
}

# This checks both the intended release and that detector definitions and test
# constructions do not make either script match itself.
expect_clean "clean AutoAssist release root" "$ROOT"

new_case
case_root="$REPLY"
digest_one='f2575103'
digest_one+='368bc7d5'
digest_one+='a5e92b66'
digest_one+='9cdae34c'
digest_one+='cbe49d27'
digest_one+='589d52e0'
digest_one+='3cf45651'
digest_one+='5d8d2949'
digest_two='0756ce90'
digest_two+='e1a8896b'
digest_two+='4c19c51c'
digest_two+='c324392a'
digest_two+='3b596283'
digest_two+='c7a2fb'"bc"
digest_two+='ed634f76'
digest_two+='1ba31ea1'
[[ ${#digest_one} -eq 64 && ${#digest_two} -eq 64 ]] || fail "nonzero digest fixture construction"
/usr/bin/printf '%s  %s\n' "$digest_one" 'AutoAssist-v1.0.0.zip' > "$case_root/AutoAssist-v1.0.0.zip.sha256"
/usr/bin/printf '%s  %s\n' "$digest_one" 'Install.command' > "$case_root/AutoAssist-v1.0.0.manifest.sha256"
/usr/bin/printf '%s  %s\n' "$digest_two" 'SECURITY.md' >> "$case_root/AutoAssist-v1.0.0.manifest.sha256"
expect_clean "valid SHA-256 sidecars" "$case_root"

new_case
case_root="$REPLY"
sidecar_path='/'"Users/"'ReleaseOwner/AutoAssist-v1.0.0.zip'
/usr/bin/printf '%s  %s\n' "$digest_one" "$sidecar_path" > "$case_root/metadata.sha256"
expect_rejection "absolute home path in SHA-256 sidecar" "$case_root" "home_path_macos" "$sidecar_path"

new_case
case_root="$REPLY"
/usr/bin/printf '%s  %s\n' "${digest_one[1,63]}" 'AutoAssist-v1.0.0.zip' > "$case_root/metadata.sha256"
expect_rejection "malformed SHA-256 digest" "$case_root" "checksum_manifest_malformed"

new_case
case_root="$REPLY"
/usr/bin/printf '%s  %s\n' "$digest_one" '../private.txt' > "$case_root/metadata.sha256"
expect_rejection "unsafe checksum path" "$case_root" "checksum_path_invalid"

new_case
case_root="$REPLY"
/bin/mkdir -p "$case_root/config"
/usr/bin/printf 'input.txt\n' > "$case_root/config/release-allowlist.txt"
mapped_payload='release.mapping'"@"'invalid.example'
/usr/bin/printf '%s\n' "$mapped_payload" > "$case_root/input.txt"
expect_rejection "deterministic allowlist diagnostic mapping" "$case_root" "email_address" "$mapped_payload" "allowlist-000001"

new_case
case_root="$REPLY"
/usr/bin/printf 'ordinary release text\n' > "$case_root/input.txt"
/bin/mkdir -p "$case_root/dist" "$case_root/.release" "$case_root/state"
/usr/bin/printf 'PK\003\004prior release\n' > "$case_root/dist/prior.zip"
/usr/bin/printf 'PK\003\004private cache\n' > "$case_root/.release/cache.zip"
pruned_payload='/'"Users/"'PrivateOwner/configured-state'
/usr/bin/printf '%s\n' "$pruned_payload" > "$case_root/state/private.txt"
pruned_hash_before="$(/usr/bin/shasum -a 256 "$case_root/state/private.txt" | /usr/bin/awk '{print $1}')"
expect_clean "top-level generated and configured directories are pruned" "$case_root"
pruned_hash_after="$(/usr/bin/shasum -a 256 "$case_root/state/private.txt" | /usr/bin/awk '{print $1}')"
[[ "$pruned_hash_before" == "$pruned_hash_after" ]] || fail "pruned configured data changed during scanning"
pass "pruned configured data is not mutated"

new_case
case_root="$REPLY"
/usr/bin/printf 'ordinary text\n' > "$case_root/target.txt"
/bin/ln -s 'target.txt' "$case_root/linked.txt"
expect_rejection "symbolic link" "$case_root" "symlink"

new_case
case_root="$REPLY"
/usr/bin/mkfifo "$case_root/pipe"
expect_rejection "nonregular FIFO" "$case_root" "nonregular_entry"

new_case
case_root="$REPLY"
/usr/bin/printf 'ordinary text\n' > "$case_root/source.txt"
/bin/ln "$case_root/source.txt" "$case_root/alias.txt"
expect_rejection "hardlinked regular file" "$case_root" "hardlinked_file"

new_case
case_root="$REPLY"
/usr/bin/printf 'ordinary text\n' > "$case_root/.env"
expect_rejection "hidden forbidden file" "$case_root" "unexpected_hidden_path"

new_case
case_root="$REPLY"
/usr/bin/printf 'ordinary text\n' > "$case_root/id_rsa"
expect_rejection "visible forbidden credential filename" "$case_root" "forbidden_filename"

new_case
case_root="$REPLY"
/usr/bin/printf '\377\n' > "$case_root/input.txt"
expect_rejection "invalid UTF-8" "$case_root" "invalid_utf8_content"

new_case
case_root="$REPLY"
/usr/bin/printf 'safe\000text\n' > "$case_root/input.txt"
expect_rejection "NUL-bearing binary" "$case_root" "binary_nul"

new_case
case_root="$REPLY"
/usr/bin/printf 'safe\001text\n' > "$case_root/input.txt"
expect_rejection "control-bearing binary" "$case_root" "binary_control"

new_case
case_root="$REPLY"
/usr/bin/printf 'PK\003\004synthetic\n' > "$case_root/input.txt"
expect_rejection "archive magic" "$case_root" "archive_zip"

new_case
case_root="$REPLY"
payload='/'"Users/"'ReleaseOwner/project/file.txt'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "macOS home path" "$case_root" "home_path_macos" "$payload"

new_case
case_root="$REPLY"
payload='/'"home/"'releaseowner/project/file.txt'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "Linux home path" "$case_root" "home_path_linux" "$payload"

new_case
case_root="$REPLY"
payload='/'"root/"'project/file.txt'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "root user home path" "$case_root" "home_path_root" "$payload"

new_case
case_root="$REPLY"
payload='/'"mnt/c/"'Users/ReleaseOwner/project/file.txt'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "WSL home path" "$case_root" "home_path_wsl" "$payload"

new_case
case_root="$REPLY"
payload='C:'\\'Users'\\'ReleaseOwner'\\'project'\\'file.txt'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "Windows home path" "$case_root" "home_path_windows" "$payload"

new_case
case_root="$REPLY"
payload='release.owner'"@"'invalid.example'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "email address" "$case_root" "email_address" "$payload"

new_case
case_root="$REPLY"
payload='+'"1"'650'"555"'0199'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "phone number" "$case_root" "phone_number" "$payload"

new_case
case_root="$REPLY"
payload='+'"44 20 7946 "'0958'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "international phone number" "$case_root" "phone_number" "$payload"

new_case
case_root="$REPLY"
payload='-----BEG''IN OPENSSH PRIV''ATE KEY-----'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "private key marker" "$case_root" "private_key_material" "$payload"

new_case
case_root="$REPLY"
payload='pass''word=synthetic-value-1234'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "credential assignment" "$case_root" "credential_assignment" "$payload"

new_case
case_root="$REPLY"
payload='API_''KEY=SYNTHETIC-VALUE-5678'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "uppercase credential assignment" "$case_root" "credential_assignment" "$payload"

new_case
case_root="$REPLY"
token_body='abcdefghijklmnop'
token_body+='qrstuvwxyz123456'
payload='s''k-'"$token_body"
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "provider token" "$case_root" "provider_token" "$payload"

new_case
case_root="$REPLY"
jwt_one='eyJhbGciOiJIUzI1NiJ9'
jwt_two='eyJzdWIiOiIxMjM0NTY3ODkwIn0'
jwt_three='YWJjZGVmZ2hpamtsbW5vcA'
payload="$jwt_one.$jwt_two.$jwt_three"
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "JSON web token" "$case_root" "jwt" "$payload"

new_case
case_root="$REPLY"
bearer_body='abcdefghijklmnop'
bearer_body+='qrstuvwxyz123456'
payload='Authoriz''ation: Bearer '"$bearer_body"
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "authorization header" "$case_root" "authorization_header" "$payload"

new_case
case_root="$REPLY"
url_scheme='https'
url_user='release'
url_pass='synthetic-value'
url_host='invalid.example'
url_separator='://'
url_at='@'
payload="${url_scheme}${url_separator}${url_user}:${url_pass}${url_at}${url_host}/path"
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "credential-bearing URL" "$case_root" "credential_url" "$payload"

new_case
case_root="$REPLY"
/usr/bin/printf 'safe\342\200\256text\n' > "$case_root/input.txt"
expect_rejection "bidirectional override" "$case_root" "hidden_unicode"

new_case
case_root="$REPLY"
/usr/bin/printf 'safe\342\200\213text\n' > "$case_root/input.txt"
expect_rejection "zero-width character" "$case_root" "hidden_unicode"

new_case
case_root="$REPLY"
escape_slash='\'
payload="safe${escape_slash}u202Etext"
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "escaped bidirectional override" "$case_root" "hidden_unicode"

new_case
case_root="$REPLY"
payload='release.owner%''40invalid.example'
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "percent-encoded email" "$case_root" "email_address"

new_case
case_root="$REPLY"
plain='api_''key=synthetic-value-1234'
payload="$(/usr/bin/printf '%s' "$plain" | /usr/bin/base64)"
/usr/bin/printf '%s\n' "$payload" > "$case_root/input.txt"
expect_rejection "Base64-encoded credential" "$case_root" "credential_assignment" "$payload"

if [[ "${AUTOASSIST_PACKAGE_PARENT:-0}" != "1" ]]; then
  repeat_sha256_pattern='^[0-9a-f]{64}$'
  new_case
  repeat_root="$REPLY/AutoAssist"
  /bin/mkdir -p "$repeat_root"
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    [[ -f "$ROOT/$entry" && ! -L "$ROOT/$entry" ]] || fail "repeat-package fixture has an invalid allowlist entry"
    /bin/mkdir -p "$repeat_root/${entry:h}"
    /bin/cp -p "$ROOT/$entry" "$repeat_root/$entry"
  done < "$ROOT/config/release-allowlist.txt"

  repeat_version="$(<"$repeat_root/VERSION")"
  repeat_archive="$repeat_root/dist/AutoAssist-v${repeat_version}.zip"
  repeat_checksum="$repeat_archive.sha256"
  repeat_manifest="$repeat_root/dist/AutoAssist-v${repeat_version}.manifest.sha256"
  first_package_log="$TEST_TEMP/repeat-package-first.log"
  second_package_log="$TEST_TEMP/repeat-package-second.log"

  if ! "$repeat_root/scripts/package.sh" > "$first_package_log" 2>&1; then
    fail "first isolated package build"
  fi
  [[ -f "$repeat_archive" && -f "$repeat_checksum" && -f "$repeat_manifest" ]] || fail "first isolated package outputs"

  /bin/mkdir -p "$repeat_root/state" "$repeat_root/.release" "$repeat_root/dist"
  repeat_private='/'"Users/"'ConfiguredOwner/runtime-state'
  repeat_state_private="$repeat_root/state/private.txt"
  repeat_release_private="$repeat_root/.release/private.zip"
  repeat_dist_private="$repeat_root/dist/private-sentinel.txt"
  /usr/bin/printf '%s\n' "$repeat_private" > "$repeat_state_private"
  /usr/bin/printf 'PK\003\004private cache\n' > "$repeat_release_private"
  /usr/bin/printf '%s\n' "$repeat_private" > "$repeat_dist_private"
  repeat_state_hash="$(/usr/bin/shasum -a 256 "$repeat_state_private" | /usr/bin/awk '{print $1}')"
  repeat_release_hash="$(/usr/bin/shasum -a 256 "$repeat_release_private" | /usr/bin/awk '{print $1}')"
  repeat_dist_hash="$(/usr/bin/shasum -a 256 "$repeat_dist_private" | /usr/bin/awk '{print $1}')"
  /bin/chmod 000 "$repeat_state_private" "$repeat_release_private" "$repeat_dist_private"
  [[ ! -r "$repeat_state_private" && ! -r "$repeat_release_private" && ! -r "$repeat_dist_private" ]] \
    || fail "repeat-package fixture did not enforce unreadable excluded files"

  if ! "$repeat_root/scripts/package.sh" > "$second_package_log" 2>&1; then
    /bin/chmod 600 "$repeat_state_private" "$repeat_release_private" "$repeat_dist_private" 2>/dev/null || true
    fail "second isolated package build"
  fi
  /bin/chmod 600 "$repeat_state_private" "$repeat_release_private" "$repeat_dist_private"
  [[ -f "$repeat_archive" && -f "$repeat_checksum" && -f "$repeat_manifest" ]] || fail "second isolated package outputs"
  [[ "$repeat_state_hash" == "$(/usr/bin/shasum -a 256 "$repeat_state_private" | /usr/bin/awk '{print $1}')" \
    && "$repeat_release_hash" == "$(/usr/bin/shasum -a 256 "$repeat_release_private" | /usr/bin/awk '{print $1}')" \
    && "$repeat_dist_hash" == "$(/usr/bin/shasum -a 256 "$repeat_dist_private" | /usr/bin/awk '{print $1}')" ]] \
    || fail "repeat package mutated configured state"

  repeat_listing="$(/usr/bin/unzip -Z1 "$repeat_archive")"
  if /usr/bin/printf '%s\n' "$repeat_listing" | /usr/bin/grep -Eq '(^|/)(dist|state|[.]release)/'; then
    fail "repeat package admitted a pruned directory"
  fi
  repeat_checksum_record="$(<"$repeat_checksum")"
  [[ "${repeat_checksum_record[1,64]}" =~ $repeat_sha256_pattern \
    && "${repeat_checksum_record[65,66]}" == "  " \
    && "${repeat_checksum_record[67,-1]}" == "${repeat_archive:t}" ]] \
    || fail "repeat package checksum grammar"
  repeat_metadata="$TEST_TEMP/repeat-package-metadata"
  /bin/mkdir -p "$repeat_metadata"
  /bin/cp "$repeat_checksum" "$repeat_manifest" "$repeat_metadata/"
  expect_clean "repeat package metadata scan" "$repeat_metadata"
  pass "two consecutive isolated package builds"
fi

/usr/bin/printf 'AutoAssist privacy scanner tests passed; assertions=%d.\n' "$assertions"
