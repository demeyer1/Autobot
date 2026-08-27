#!/bin/zsh

# Deterministic, fail-closed release scanner. Findings intentionally contain
# only stable file identifiers and rule names, never paths or matched values.
emulate -LR zsh
set -eu
setopt pipe_fail
export LC_ALL=C
export LANG=C
export TZ=UTC

ROOT_INPUT="${1:-${0:A:h:h}}"
MAX_FILE_BYTES=$((2 * 1024 * 1024))
MAX_LINE_BYTES=$((256 * 1024))
MAX_DECODE_INPUT=16384
MAX_BASE64_CANDIDATES_PER_FILE=256
MAX_PRINTED_FINDINGS=200

if [[ -L "$ROOT_INPUT" || ! -d "$ROOT_INPUT" ]]; then
  /bin/echo "AutoAssist privacy scan could not inspect the requested root." >&2
  exit 2
fi

ROOT="$(cd -P -- "$ROOT_INPUT" 2>/dev/null && /bin/pwd -P)" || {
  /bin/echo "AutoAssist privacy scan could not resolve the requested root." >&2
  exit 2
}

HOME_CANON=""
if [[ -n "${HOME:-}" && -d "$HOME" ]]; then
  HOME_CANON="$(cd -P -- "$HOME" 2>/dev/null && /bin/pwd -P)" || HOME_CANON=""
fi
if [[ "$ROOT" == "/" || ( -n "$HOME_CANON" && "$ROOT" == "$HOME_CANON" ) ]]; then
  /bin/echo "AutoAssist privacy scan refuses a broad filesystem root." >&2
  exit 2
fi

SCAN_TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/autoassist-privacy.XXXXXX")" || {
  /bin/echo "AutoAssist privacy scan could not create isolated scratch space." >&2
  exit 2
}
MANIFEST="$SCAN_TEMP/manifest.bin"
DECODED="$SCAN_TEMP/decoded.bin"
cleanup() {
  /bin/rm -f -- "$MANIFEST" "$DECODED" 2>/dev/null || true
  /bin/rmdir -- "$SCAN_TEMP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

integer findings=0
integer printed_findings=0

record_finding() {
  local rule="$1"
  local file_id="${2:-root}"
  local line_number="${3:-0}"
  local view="${4:-raw}"
  findings=$((findings + 1))
  if (( printed_findings < MAX_PRINTED_FINDINGS )); then
    /usr/bin/printf 'FAIL rule=%s file=%s line=%s view=%s value=[REDACTED]\n' \
      "$rule" "$file_id" "$line_number" "$view" >&2
    printed_findings=$((printed_findings + 1))
  fi
}

has_nul_byte() {
  /usr/bin/od -An -v -tx1 -- "$1" 2>/dev/null |
    /usr/bin/grep -Eq '(^|[[:space:]])00([[:space:]]|$)'
}

has_forbidden_control_byte() {
  /usr/bin/od -An -v -tx1 -- "$1" 2>/dev/null |
    /usr/bin/grep -Eq '(^|[[:space:]])(0[1-8bcef]|1[0-9a-f]|7f)([[:space:]]|$)'
}

stream_has_forbidden_control_byte() {
  /usr/bin/od -An -v -tx1 2>/dev/null |
    /usr/bin/grep -Eq '(^|[[:space:]])(0[0-8bcef]|1[0-9a-f]|7f)([[:space:]]|$)'
}

archive_magic_rule() {
  local magic
  magic="$(/usr/bin/od -An -v -tx1 -N 16 -- "$1" 2>/dev/null | /usr/bin/tr -d ' \n')"
  case "$magic" in
    (504b0304*|504b0506*|504b0708*) REPLY="archive_zip" ;;
    (1f8b*) REPLY="archive_gzip" ;;
    (425a68*) REPLY="archive_bzip2" ;;
    (fd377a585a00*) REPLY="archive_xz" ;;
    (377abcaf271c*) REPLY="archive_7zip" ;;
    (526172211a0700*|526172211a070100*) REPLY="archive_rar" ;;
    (53514c69746520666f726d61742033*) REPLY="database_sqlite" ;;
    (25504446*) REPLY="document_pdf" ;;
    (7f454c46*|feedface*|feedfacf*|cefaedfe*|cffaedfe*) REPLY="native_executable" ;;
    (*) REPLY="" ;;
  esac
}

file_size() {
  local value
  if value="$(/usr/bin/stat -f '%z' "$1" 2>/dev/null)"; then
    REPLY="$value"
  elif value="$(/usr/bin/stat -c '%s' "$1" 2>/dev/null)"; then
    REPLY="$value"
  else
    REPLY=""
    return 1
  fi
}

hardlink_count() {
  local value
  if value="$(/usr/bin/stat -f '%l' "$1" 2>/dev/null)"; then
    REPLY="$value"
  elif value="$(/usr/bin/stat -c '%h' "$1" 2>/dev/null)"; then
    REPLY="$value"
  else
    REPLY=""
    return 1
  fi
}

allowlist_reference() {
  local relative="$1"
  local fallback="$2"
  local entry
  integer ordinal=0
  local allowlist="$ROOT/config/release-allowlist.txt"

  REPLY="$fallback"
  [[ -f "$allowlist" && ! -L "$allowlist" ]] || return 0
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    ordinal=$((ordinal + 1))
    if [[ "$entry" == "$relative" ]]; then
      REPLY="$(/usr/bin/printf 'allowlist-%06d' "$ordinal")"
      return 0
    fi
  done < "$allowlist"
}

# Signatures are deliberately assembled so the scanner source does not contain
# live examples of the values it rejects.
email_pattern='[A-Za-z0-9][A-Za-z0-9._%+-]{0,63}[@][A-Za-z0-9][A-Za-z0-9.-]{0,190}[.][A-Za-z]{2,24}'
phone_pattern='(^|[^0-9])([+]?[0-9]{1,3}[ .()-]+)?[2-9][0-9]{2}[ .()-]+[0-9]{3}[ .-]+[0-9]{4}([^0-9]|$)|(^|[^0-9])[+]?1?[2-9][0-9]{9}([^0-9]|$)'
international_phone_pattern='(^|[^0-9])[+][0-9][0-9 .()-]{7,20}[0-9]([^0-9]|$)'
mac_home_pattern='(^|[^[:alnum:]_])[/]us[e]rs[/][a-z0-9._-]{1,64}([/]|$)'
linux_home_pattern='(^|[^[:alnum:]_])[/]ho[m]e[/][a-z0-9._-]{1,64}([/]|$)'
root_home_pattern='(^|[^[:alnum:]_])[/]ro[o]t([/]|$)'
wsl_home_pattern='(^|[^[:alnum:]_])[/]m[n]t[/][a-z][/]us[e]rs[/][a-z0-9._-]{1,64}([/]|$)'
windows_home_pattern='(^|[^[:alnum:]_])[a-z]:[\\/]+us[e]rs[\\/]+[a-z0-9._-]{1,64}([\\/]|$)'
private_key_pattern='BEG[I]N (RSA |EC |DSA |OPENSSH |PGP )?PRIV[A]TE KEY'
credential_name_pattern='(pass[w]ord|pass[w]d|passph[r]ase|api[_-]?k[e]y|access[_-]?tok[e]n|refresh[_-]?tok[e]n|client[_-]?secr[e]t|auth[_-]?tok[e]n|webhook[_-]?secr[e]t|signing[_-]?k[e]y|session[_-]?(cookie|tok[e]n)|private[_-]?k[e]y|recovery[_-]?k[e]y|otp|mfa[_-]?code)'
credential_assignment_pattern="(^|[^[:alnum:]_])['\"]?${credential_name_pattern}['\"]?[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9+/_.=@:-]{8,}"
provider_token_pattern='(s[k]-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_p[a]t_[A-Za-z0-9_]{20,}|xo[x][abprs]-[A-Za-z0-9-]{10,}|A(KIA|SIA)[A-Z0-9]{16}|AIz[a][A-Za-z0-9_-]{30,}|s[k]_(live|test)_[A-Za-z0-9]{16,}|np[m]_[A-Za-z0-9]{20,}|h[f]_[A-Za-z0-9]{20,}|S[K][0-9a-fA-F]{32}|S[G][.][A-Za-z0-9_-]{16,}[.][A-Za-z0-9_-]{16,})'
jwt_pattern='eyJ[A-Za-z0-9_-]{8,}[.]eyJ[A-Za-z0-9_-]{8,}[.][A-Za-z0-9_-]{8,}'
auth_header_pattern='authoriz[a]tion[[:space:]]*:[[:space:]]*(bearer|basic)[[:space:]]+[a-z0-9+/_=.-]{8,}'
credential_url_pattern='[A-Za-z][A-Za-z0-9+.-]*://[^/@:[:space:]]+:[^/@[:space:]]+@[^/[:space:]]+'
scaffold_pattern='\[''TODO:|TODO_''AUTOASSIST|REPLACE_''WITH_REAL'
sha256_pattern='^[0-9a-f]{64}$'
checksum_path_pattern='^[A-Za-z0-9._+@ -]+(/[A-Za-z0-9._+@ -]+)*$'

typeset -a hidden_chars
hidden_chars=(
  $'\302\255'
  $'\330\234'
  $'\342\200\213' $'\342\200\214' $'\342\200\215'
  $'\342\200\216' $'\342\200\217'
  $'\342\200\252' $'\342\200\253' $'\342\200\254' $'\342\200\255' $'\342\200\256'
  $'\342\201\240' $'\342\201\246' $'\342\201\247' $'\342\201\250' $'\342\201\251'
  $'\357\273\277'
)

scan_text_value() {
  local value="$1"
  local file_id="$2"
  local line_number="$3"
  local view="$4"
  local hidden normalized

  normalized="${value:l}"

  [[ "$normalized" =~ $mac_home_pattern ]] && record_finding "home_path_macos" "$file_id" "$line_number" "$view"
  [[ "$normalized" =~ $linux_home_pattern ]] && record_finding "home_path_linux" "$file_id" "$line_number" "$view"
  [[ "$normalized" =~ $root_home_pattern ]] && record_finding "home_path_root" "$file_id" "$line_number" "$view"
  [[ "$normalized" =~ $wsl_home_pattern ]] && record_finding "home_path_wsl" "$file_id" "$line_number" "$view"
  [[ "$normalized" =~ $windows_home_pattern ]] && record_finding "home_path_windows" "$file_id" "$line_number" "$view"
  [[ "$value" =~ $email_pattern ]] && record_finding "email_address" "$file_id" "$line_number" "$view"
  [[ "$value" =~ $phone_pattern ]] && record_finding "phone_number" "$file_id" "$line_number" "$view"
  [[ "$value" =~ $international_phone_pattern ]] && record_finding "phone_number" "$file_id" "$line_number" "$view"
  [[ "$value" =~ $private_key_pattern ]] && record_finding "private_key_material" "$file_id" "$line_number" "$view"
  [[ "$normalized" =~ $credential_assignment_pattern ]] && record_finding "credential_assignment" "$file_id" "$line_number" "$view"
  [[ "$value" =~ $provider_token_pattern ]] && record_finding "provider_token" "$file_id" "$line_number" "$view"
  [[ "$value" =~ $jwt_pattern ]] && record_finding "jwt" "$file_id" "$line_number" "$view"
  [[ "$normalized" =~ $auth_header_pattern ]] && record_finding "authorization_header" "$file_id" "$line_number" "$view"
  [[ "$value" =~ $credential_url_pattern ]] && record_finding "credential_url" "$file_id" "$line_number" "$view"
  [[ "$value" =~ $scaffold_pattern ]] && record_finding "unfinished_scaffold" "$file_id" "$line_number" "$view"
  for hidden in "${hidden_chars[@]}"; do
    if [[ "$value" == *"$hidden"* ]]; then
      record_finding "hidden_unicode" "$file_id" "$line_number" "$view"
      break
    fi
  done
}

decode_base64_to_file() {
  local candidate="$1"
  local normalized="$candidate"
  local remainder
  normalized="${normalized//-/+}"
  normalized="${normalized//_/\/}"
  remainder=$(( ${#normalized} % 4 ))
  (( remainder == 1 )) && return 1
  (( remainder == 2 )) && normalized="${normalized}=="
  (( remainder == 3 )) && normalized="${normalized}="
  : >| "$DECODED"
  if /usr/bin/printf '%s' "$normalized" | /usr/bin/base64 -D >| "$DECODED" 2>/dev/null; then
    return 0
  fi
  : >| "$DECODED"
  /usr/bin/printf '%s' "$normalized" | /usr/bin/base64 -d >| "$DECODED" 2>/dev/null
}

scan_decoded_file() {
  local file_id="$1"
  local source_line="$2"
  local view="$3"
  local decoded_line
  integer decoded_line_number=0
  local size

  file_size "$DECODED" || return 0
  size="$REPLY"
  [[ "$size" == <-> ]] || return 0
  (( size == 0 )) && return 0
  if (( size > MAX_DECODE_INPUT )); then
    record_finding "encoded_view_too_large" "$file_id" "$source_line" "$view"
    return 0
  fi
  has_nul_byte "$DECODED" && return 0
  has_forbidden_control_byte "$DECODED" && return 0
  /usr/bin/iconv -f UTF-8 -t UTF-8 "$DECODED" >/dev/null 2>&1 || return 0
  while IFS= read -r decoded_line || [[ -n "$decoded_line" ]]; do
    decoded_line_number=$((decoded_line_number + 1))
    scan_text_value "$decoded_line" "$file_id" "$source_line" "$view"
  done < "$DECODED"
}

scan_encoded_views() {
  local value="$1"
  local file_id="$2"
  local line_number="$3"
  local escaped candidate
  integer candidate_count_ref=$4

  if [[ "$value" =~ '%[[:xdigit:]]{2}' || "$value" =~ '\\x[[:xdigit:]]{2}' || "$value" =~ '\\u[[:xdigit:]]{4}' ]]; then
    if (( ${#value} > MAX_DECODE_INPUT )); then
      record_finding "encoded_view_too_large" "$file_id" "$line_number" "escape"
    elif [[ "$value" =~ '%0[0]' || "$value" =~ '\\x0[0]' || "$value" =~ '\\u0{3}[0]' ]]; then
      record_finding "encoded_nul" "$file_id" "$line_number" "escape"
    else
      escaped="$(/usr/bin/printf '%s' "$value" | /usr/bin/sed -E 's/%([[:xdigit:]]{2})/\\x\1/g')"
      : >| "$DECODED"
      if (
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        builtin printf '%b' "$escaped"
      ) >| "$DECODED" 2>/dev/null; then
        scan_decoded_file "$file_id" "$line_number" "escape"
      else
        record_finding "encoded_decode_failed" "$file_id" "$line_number" "escape"
      fi
    fi
  fi

  if [[ "$value" =~ '[A-Za-z0-9+/_-]{24}' ]]; then
    while IFS= read -r candidate; do
      [[ -z "$candidate" ]] && continue
      candidate_count_ref=$((candidate_count_ref + 1))
      if (( candidate_count_ref > MAX_BASE64_CANDIDATES_PER_FILE )); then
        record_finding "encoded_candidate_limit" "$file_id" "$line_number" "base64"
        break
      fi
      if (( ${#candidate} > MAX_DECODE_INPUT )); then
        record_finding "encoded_view_too_large" "$file_id" "$line_number" "base64"
        continue
      fi
      if decode_base64_to_file "$candidate"; then
        scan_decoded_file "$file_id" "$line_number" "base64"
      fi
    done < <(/usr/bin/printf '%s\n' "$value" | /usr/bin/grep -Eo '([A-Za-z0-9+/]{24,}={0,2}|[A-Za-z0-9_-]{24,})' 2>/dev/null || true)
  fi

  REPLY="$candidate_count_ref"
}

checksum_path_is_safe() {
  local value="$1"
  local segment
  typeset -a segments

  [[ -n "$value" ]] || return 1
  [[ "$value" != /* && "$value" != ./* && "$value" != ../* ]] || return 1
  [[ "$value" != *\\* && "$value" != *//* && "$value" != */ && "$value" != ' '* && "$value" != *' ' ]] || return 1
  [[ "$value" != *$'\r'* && "$value" =~ $checksum_path_pattern ]] || return 1
  segments=("${(@s:/:)value}")
  for segment in "${segments[@]}"; do
    [[ "$segment" != "." && "$segment" != ".." ]] || return 1
  done
  return 0
}

scan_checksum_line() {
  local value="$1"
  local file_id="$2"
  local line_number="$3"
  integer candidate_count_ref=$4
  local digest separator metadata_path

  if (( ${#value} < 67 )); then
    record_finding "checksum_manifest_malformed" "$file_id" "$line_number" "checksum"
    REPLY="$candidate_count_ref"
    return 0
  fi

  digest="${value[1,64]}"
  separator="${value[65,66]}"
  metadata_path="${value[67,-1]}"
  if [[ ! "$digest" =~ $sha256_pattern || "$separator" != "  " || -z "$metadata_path" ]]; then
    record_finding "checksum_manifest_malformed" "$file_id" "$line_number" "checksum"
  fi

  # Never scan the digest field as content. It is integrity metadata, not text.
  # The path portion remains fully validated and privacy-scanned.
  if [[ "$separator" == "  " && -n "$metadata_path" ]]; then
    checksum_path_is_safe "$metadata_path" || record_finding "checksum_path_invalid" "$file_id" "$line_number" "checksum-path"
    scan_text_value "$metadata_path" "$file_id" "$line_number" "checksum-path"
    scan_encoded_views "$metadata_path" "$file_id" "$line_number" "$candidate_count_ref"
    candidate_count_ref="$REPLY"
  fi
  REPLY="$candidate_count_ref"
}

# These top-level directories are generated or populated after release source
# creation. Prune them without enumerating their contents; package admission
# separately scans the freshly staged tree and generated metadata directly.
if ! /usr/bin/find "$ROOT" -mindepth 1 \
  \( -path "$ROOT/dist" -o -path "$ROOT/.release" -o -path "$ROOT/state" \) -prune -o \
  -print0 >| "$MANIFEST" 2>/dev/null; then
  record_finding "tree_enumeration_failed" "root" 0 "metadata"
fi

typeset -a paths
paths=()
while IFS= read -r -d $'\0' path; do
  paths+=("$path")
done < "$MANIFEST"
paths=("${(o)paths[@]}")

integer file_sequence=0
local_path=""
for local_path in "${paths[@]}"; do
  relative="${local_path#$ROOT/}"
  file_sequence=$((file_sequence + 1))
  file_id="$(/usr/bin/printf 'item-%06d' "$file_sequence")"
  allowlist_reference "$relative" "$file_id"
  file_id="$REPLY"
  basename="${relative:t}"
  lower_basename="${basename:l}"

  if [[ -L "$local_path" ]]; then
    record_finding "symlink" "$file_id" 0 "metadata"
    continue
  fi
  if [[ ! -d "$local_path" && ! -f "$local_path" ]]; then
    record_finding "nonregular_entry" "$file_id" 0 "metadata"
    continue
  fi

  if ! /usr/bin/printf '%s' "$relative" | /usr/bin/iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    record_finding "invalid_utf8_path" "$file_id" 0 "metadata"
  fi
  if /usr/bin/printf '%s' "$relative" | stream_has_forbidden_control_byte; then
    record_finding "control_character_path" "$file_id" 0 "metadata"
  fi
  if [[ "$relative" == .* || "$relative" == */.* ]]; then
    [[ "$relative" == ".gitignore" && -f "$local_path" ]] || record_finding "unexpected_hidden_path" "$file_id" 0 "metadata"
  fi
  if [[ "$basename" == *' ' || "$basename" == *'.' ]]; then
    record_finding "ambiguous_filename" "$file_id" 0 "metadata"
  fi

  case "$lower_basename" in
    (.env|.env.*|.npmrc|.netrc|.pypirc|.ds_store|credentials|credentials.*|secrets|secrets.*|id_rsa|id_dsa|id_ecdsa|id_ed25519|authorized_keys|known_hosts)
      record_finding "forbidden_filename" "$file_id" 0 "metadata" ;;
    (*.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|*.mobileprovision|*.cer|*.crt|*.der)
      record_finding "credential_file_type" "$file_id" 0 "metadata" ;;
    (*.zip|*.tar|*.tgz|*.gz|*.bz2|*.xz|*.7z|*.rar|*.dmg|*.pkg|*.iso|*.jar|*.war)
      record_finding "archive_file_type" "$file_id" 0 "metadata" ;;
    (*.db|*.sqlite|*.sqlite3|*.mdb|*.realm)
      record_finding "database_file_type" "$file_id" 0 "metadata" ;;
    (*.log|*.bak|*.backup|*.orig|*.rej|*.swp|*.swo|*~)
      record_finding "transient_file_type" "$file_id" 0 "metadata" ;;
  esac

  scan_text_value "$relative" "$file_id" 0 "path"

  [[ -d "$local_path" ]] && continue

  hardlink_count "$local_path" || {
    record_finding "metadata_unreadable" "$file_id" 0 "metadata"
    continue
  }
  if [[ "$REPLY" != <-> ]]; then
    record_finding "metadata_invalid" "$file_id" 0 "metadata"
    continue
  fi
  (( REPLY > 1 )) && record_finding "hardlinked_file" "$file_id" 0 "metadata"

  file_size "$local_path" || {
    record_finding "metadata_unreadable" "$file_id" 0 "metadata"
    continue
  }
  if [[ "$REPLY" != <-> ]]; then
    record_finding "metadata_invalid" "$file_id" 0 "metadata"
    continue
  fi
  if (( REPLY > MAX_FILE_BYTES )); then
    record_finding "file_too_large" "$file_id" 0 "metadata"
    continue
  fi

  archive_magic_rule "$local_path"
  [[ -n "$REPLY" ]] && record_finding "$REPLY" "$file_id" 0 "magic"
  if has_nul_byte "$local_path"; then
    record_finding "binary_nul" "$file_id" 0 "bytes"
    continue
  fi
  if has_forbidden_control_byte "$local_path"; then
    record_finding "binary_control" "$file_id" 0 "bytes"
    continue
  fi
  if ! /usr/bin/iconv -f UTF-8 -t UTF-8 "$local_path" >/dev/null 2>&1; then
    record_finding "invalid_utf8_content" "$file_id" 0 "bytes"
    continue
  fi

  integer line_number=0
  integer base64_candidates=0
  integer checksum_metadata=0
  [[ "$lower_basename" == *.sha256 ]] && checksum_metadata=1
  line=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    if (( ${#line} > MAX_LINE_BYTES )); then
      record_finding "line_too_large" "$file_id" "$line_number" "raw"
      continue
    fi
    if (( checksum_metadata )); then
      scan_checksum_line "$line" "$file_id" "$line_number" "$base64_candidates"
      base64_candidates="$REPLY"
    else
      scan_text_value "$line" "$file_id" "$line_number" "raw"
      scan_encoded_views "$line" "$file_id" "$line_number" "$base64_candidates"
      base64_candidates="$REPLY"
    fi
  done < "$local_path"
  if (( checksum_metadata && line_number == 0 )); then
    record_finding "checksum_manifest_empty" "$file_id" 0 "checksum"
  fi
done

if (( findings > printed_findings )); then
  /usr/bin/printf 'FAIL additional_findings=%d details=[REDACTED]\n' "$((findings - printed_findings))" >&2
fi

if (( findings > 0 )); then
  /usr/bin/printf 'AutoAssist privacy scan failed; findings=%d.\n' "$findings" >&2
  exit 1
fi

/bin/echo "AutoAssist privacy scan passed; findings=0."
