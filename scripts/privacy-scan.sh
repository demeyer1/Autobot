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
    (89504e47*|ffd8ff*|47494638*|52494646*) REPLY="opaque_media" ;;
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
phone_pattern='(^|[^[:alnum:]_])([+]?[0-9]{1,3}[ .()-]+)?[2-9][0-9]{2}[ .()-]+[0-9]{3}[ .-]+[0-9]{4}([^[:alnum:]_]|$)|(^|[^[:alnum:]_])[+]?1?[2-9][0-9]{9}([^[:alnum:]_]|$)'
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

# Financial detector signatures are intentionally bounded. Every valid-Luhn
# run is rejected, including non-issuer-shaped runs. The only public numeric
# controls are exact baseline lines bound to the full source path and file
# hash below; a benchmark path or field label alone never disables the check.
cvv_pattern='(^|[^[:alnum:]_])(cvv|cvc|cvv2|cvc2|cvn|cvn2|cid|card[ _-]*identification([ _-]*number)?|security[ _-]+code)([ _-]+(number|code))?[- _*"]*[:=#-]?[- _*"]*[0-9]{3,4}([^0-9]|$)'
pin_pattern='(^|[^[:alnum:]_])(pin|pin[ _-]+code|passcode|security[ _-]+pin)([ _-]+(number|code))?[- _*"]*[:=#-]?[- _*"]*[0-9]{4,8}([^0-9]|$)'
pin_block_pattern='(^|[^[:alnum:]_])((encrypted[ _-]*)?pin[ _-]*block)[- _*"]*[:=#-]?[- _*"]*[0-9a-f]{8,}([^0-9a-f]|$)'
routing_pattern='(^|[^[:alnum:]_])(routing|routing[ _-]+number|aba|aba[ _-]+routing|transit[ _-]+number|institution[ _-]+number)[- _*"]*([:=#-][- _*"]*|[- _*"]+)[0-9]([-0-9 _*"]{7,14}[0-9])?([^0-9]|$)'
account_pattern='(^|[^[:alnum:]_])(bank[ _-]+account|account[ _-]+number|checking[ _-]+account|savings[ _-]+account)[- _*"]*([:=#-][- _*"]*|[- _*"]+)[0-9]([-0-9 _*"]{2,32}[0-9])?([^0-9]|$)'
iban_pattern='(^|[^[:alnum:]_])iban[ _-]*[:=#-]?[- _*"]*[a-z]{2}[0-9a-z]([-0-9a-z _*"]{12,32}[0-9a-z])?([^0-9a-z]|$)'
expiry_pattern='(^|[^[:alnum:]_])(expiry|expiration|exp[ _-]*(iry|iration)|valid[ _-]*(thru|through)|card[ _-]*expiry)([ _-]*(date|month|year))?[- _*"]*[:=#-]?[- _*"]*[0-9]{1,4}([[:space:]./-]+[0-9]{2,4})?([^0-9]|$)'
payment_token_pattern='(^|[^[:alnum:]_])(((payment|card|billing|network|source)[ _-]*(token|method[ _-]*id))|tokenized[ _-]*pan)[- _*"]*[:=][- _*"]*[a-z0-9_-]{8,}([^a-z0-9_-]|$)|(^|[^[:alnum:]_])tok_[a-z0-9_-]{8,}([^a-z0-9_-]|$)'
payment_token_placeholder_pattern='(^|[^[:alnum:]_])(((payment|card|billing|network|source)[ _-]*(token|method[ _-]*id))|tokenized[ _-]*pan)[- _*"]*[:=][- _*"]*(redacted|placeholder|synthetic|example|none|null|unknown|masked|n/?a)([^a-z0-9_-]|$)'
masked_card_pattern='(^|[^[:alnum:]_])(card|credit[ _-]*card|debit[ _-]*card|pan|billing[ _-]*card)[- _*":=]*([*xX#•·][- _*.]*)([*xX#•·][- _*.]*)[0-9]{4}([^0-9]|$)'
masked_card_number_pattern='(^|[^[:alnum:]_])(card|credit[ _-]*card|debit[ _-]*card|pan|billing[ _-]*card)[ _-]*number[- _*":=]*([*xX#•·][- _*.]*)([*xX#•·][- _*.]*)[0-9]{4}([^0-9]|$)'
service_code_pattern='(^|[^[:alnum:]_])service[ _-]*code[- _*"]*[:=#-]?[- _*"]*[0-9]{3,4}([^0-9]|$)'
track_one_pattern='(^|[[:space:]])%B[0-9]{12,19}[\^][^[:space:]\^]{1,64}[\^][0-9]{4,6}[?]'
track_two_pattern='(^|[^0-9])[;][0-9]{12,19}=[0-9]{4,6}[?]([^0-9]|$)'
track_one_fragment_pattern='(^|[[:space:]])%B[0-9 ./-]{4,}'
track_two_fragment_pattern='(^|[^0-9])[;][0-9 ./-]{4,}(=|$)'
labelled_track_pattern='(^|[^[:alnum:]_])track[ _-]*(1|2|one|two)[ _*"`-]*[:=#-][ _*"`-]*[0-9]{4,19}='
context_card_pattern='(^|[^[:alnum:]])(card|credit[ _-]+card|debit[ _-]+card|pan|primary[ _-]+account|billing([ _-]+(card|account|payment|number))?)([^[:alnum:]]|$)'
MAX_FINANCIAL_CANDIDATES_PER_LINE=256

financial_tail=""

decode_numeric_entities() {
  local value="$1"
  if [[ "$value" == *'&#'* && -x /usr/bin/perl ]]; then
    REPLY="$(/usr/bin/perl -CS -pe 's/&#x([0-9a-fA-F]{1,6});/chr(hex($1))/ge; s/&#([0-9]{1,7});/chr($1)/ge' <<< "$value")"
  else
    REPLY="$value"
  fi
}

normalize_decimal_digits() {
  local value="$1"
  local decoded
  decode_numeric_entities "$value"
  decoded="$REPLY"
  if [[ "$decoded" == *[![:ascii:]]* && -x /usr/bin/perl ]]; then
    REPLY="$(/usr/bin/perl -MUnicode::UCD -CS -pe 's/(\p{Nd})/Unicode::UCD::charinfo(ord($1))->{digit}/ge' <<< "$decoded")"
  else
    REPLY="$decoded"
  fi
}

luhn_valid() {
  local digits="$1"
  [[ "$digits" =~ '^[0-9]{12,19}$' ]] || return 1
  integer sum=0 alternate=0 index value digit
  for ((index=${#digits}; index > 0; index--)); do
    digit="${digits[index]}"
    value=$digit
    if (( alternate )); then
      value=$((value * 2))
      if (( value > 9 )); then value=$((value - 9)); fi
    fi
    sum=$((sum + value))
    alternate=$((1 - alternate))
  done
  (( sum % 10 == 0 ))
}

card_issuer_length_context() {
  local digits="$1"
  integer length=${#digits} first_two first_three first_four
  first_two=$((10#${digits[1,2]}))
  first_three=$((10#${digits[1,3]}))
  first_four=$((10#${digits[1,4]}))
  if [[ "$digits[1]" == '4' ]]; then
    [[ "$length" == 13 || "$length" == 16 || "$length" == 19 ]]
  elif (( first_two == 34 || first_two == 37 )); then
    (( length == 15 ))
  elif (( (first_two >= 51 && first_two <= 55) || (first_four >= 2221 && first_four <= 2720) )); then
    (( length == 16 ))
  elif [[ "$digits" == 6011* ]] || (( first_two == 65 || (first_three >= 644 && first_three <= 649) )); then
    [[ "$length" == 16 || "$length" == 19 ]]
  elif (( first_four >= 3528 && first_four <= 3589 )); then
    (( length >= 16 && length <= 19 ))
  elif (( first_two == 62 )); then
    (( length >= 16 && length <= 19 ))
  elif (( (first_three >= 300 && first_three <= 305) || first_two == 36 || first_two == 38 )); then
    (( length == 14 ))
  else
    return 1
  fi
}

is_explicit_placeholder() {
  local value="${1:l}"
  case "$value" in
    redacted|placeholder|synthetic|example|none|null|unknown|masked|n/a|na|card_number|card-number|'card number') return 0 ;;
    *) return 1 ;;
  esac
}

scan_payment_tokens() {
  local value="$1"
  local token
  while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    is_explicit_placeholder "$token" || { record_finding "payment_token" "$2" "$3" "$4"; return; }
  done < <(/usr/bin/perl -CS -ne 'while(/(?<![A-Za-z0-9_])(?:(?:(?:payment|card|billing|network|source)[ _-]*(?:token|method[ _-]*id)|tokenized[ _-]*pan)[\s"\x27`_-]*[:=#-][\s"\x27`_-]*([A-Za-z0-9_-]+)|((?:tok_)[A-Za-z0-9_-]+))(?![A-Za-z0-9_-])/ig){print(($1 // $2), "\n")}' <<< "$value")
}

scan_named_text_fields() {
  local value="$1"
  local rule field_value
  while IFS=$'\t' read -r rule field_value; do
    [[ -n "$field_value" ]] || continue
    is_explicit_placeholder "$field_value" || { record_finding "$rule" "$2" "$3" "$4"; return; }
  done < <(/usr/bin/perl -CS -ne 'while(/(?<![A-Za-z0-9_])((?:billing[ _-]*address|card[ _-]*holder(?:[ _-]*name)?)[\s"\x27`_-]*[:=#-][\s_-]*(?:"([^"\r\n]*)"|\x27([^\x27\r\n]*)\x27|([^\s,;}]+)))/ig){my $v=defined($2)?$2:(defined($3)?$3:($4 // ""));my $r=$1 =~ /billing/i ? "billing_field" : "cardholder_name";print "$r\t$v\n"}' <<< "$value")
}

current_relative=""
current_source_sha256=""
current_line_raw=""

# The baseline rows below are public, unchanged benchmark bytes. A whole-line
# SHA-256 plus the exact file SHA-256/path is the shell scanner's equivalent
# of the Node scanner's run binding. No arbitrary metric-labelled text can
# reach this allow path, and any changed byte falls through to rejection.
benchmark_line_is_admitted() {
  local line_number="$1"
  local view="$2"
  local line="$3"
  local expected_line_sha256=""
  if [[ "$view" == raw ]]; then
    line="$3"
  elif [[ "$view" == split ]]; then
    line="$current_line_raw"
  else
    return 1
  fi
  case "$current_relative:$current_source_sha256:$line_number" in
    (benchmarks/osworld-2.0/results.csv:ceaec4c2c4a668f2a4f37286bf5d95d329382b1a12a744ce2b826e9ebc1d6c7e:15) expected_line_sha256='4ab24b76abb2c16d6fcfb7d0c2bdb365de3b8cfee5876e50db029aa1d5d0a1ca' ;;
    (benchmarks/osworld-2.0/results.csv:ceaec4c2c4a668f2a4f37286bf5d95d329382b1a12a744ce2b826e9ebc1d6c7e:39) expected_line_sha256='5e9d40b998c7a018a4543b17a3042ecbb0e60d983ee8ee3c6c43095ee0314aca' ;;
    (benchmarks/osworld-2.0/results.csv:ceaec4c2c4a668f2a4f37286bf5d95d329382b1a12a744ce2b826e9ebc1d6c7e:40) expected_line_sha256='559b030ac606b191dad09696e4d6062248ed37358df48885374d6a93a5befbde' ;;
    (benchmarks/osworld-2.0/results.csv:ceaec4c2c4a668f2a4f37286bf5d95d329382b1a12a744ce2b826e9ebc1d6c7e:54) expected_line_sha256='aca2cfe3271b3706d8a587037e7d2b371ab4123851370b74b8cc294083073490' ;;
    (benchmarks/osworld-2.0/results.csv:ceaec4c2c4a668f2a4f37286bf5d95d329382b1a12a744ce2b826e9ebc1d6c7e:81) expected_line_sha256='3af888494f2e36f5737227528ef5d37bf28228e717ded9394da707c85b96b009' ;;
    (benchmarks/osworld-2.0/results.csv:ceaec4c2c4a668f2a4f37286bf5d95d329382b1a12a744ce2b826e9ebc1d6c7e:90) expected_line_sha256='853db816e97c6aad313f45e8618ccef7862249730b6a2f8932e460818ab12323' ;;
    (benchmarks/osworld-2.0/results.csv:ceaec4c2c4a668f2a4f37286bf5d95d329382b1a12a744ce2b826e9ebc1d6c7e:105) expected_line_sha256='8742f2cb189a5339a90322b8377068aea73678412001ea7a45b132f9790d2832' ;;
    (benchmarks/osworld-2.0/results.csv:ceaec4c2c4a668f2a4f37286bf5d95d329382b1a12a744ce2b826e9ebc1d6c7e:107) expected_line_sha256='599f22c5e8eb447bb6b6589c2dfed6c2d6186aaf26a38bf6089af3d9edaf19db' ;;
    (benchmarks/osworld-2.0/score-evidence.json:3a9ce372820b3382a8f37cc0f567b83f24f5a04adcce0b1c7bd9e0c2b5f5ace1:112) expected_line_sha256='38220e161f326262d266cf09be48646e4e754568904df36201b9f50d4febeebb' ;;
    (benchmarks/osworld-2.0/score-evidence.json:3a9ce372820b3382a8f37cc0f567b83f24f5a04adcce0b1c7bd9e0c2b5f5ace1:305) expected_line_sha256='66c3d431cfb761dfdaf24638a77f8663813462110031a2552111da762e7ac390' ;;
    (benchmarks/osworld-2.0/summary.json:dcdda182d4ec704e368f748779a113d1d53daf2b34d0e1a8e74ddefe7d9d6e27:15) expected_line_sha256='b975da3c077ec71224bfa2f73a4322c6637dc84364e225997c4a4bba153ea0d9' ;;
    (*) return 1 ;;
  esac
  local actual_line_sha256
  actual_line_sha256="$(/usr/bin/printf '%s' "$line" | /usr/bin/shasum -a 256 2>/dev/null)" || return 1
  actual_line_sha256="${actual_line_sha256%% *}"
  [[ "$actual_line_sha256" == "$expected_line_sha256" ]]
}

scan_financial_value() {
  local value="$1"
  local file_id="$2"
  local line_number="$3"
  local view="$4"
  local normalized lowered candidate digits
  integer candidates=0

  normalize_decimal_digits "$value"
  normalized="$REPLY"
  lowered="${normalized:l}"
  scan_payment_tokens "$value" "$file_id" "$line_number" "$view"
  scan_named_text_fields "$value" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $cvv_pattern ]] && record_finding "payment_cvv" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $pin_pattern ]] && record_finding "payment_pin" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $pin_block_pattern ]] && record_finding "pin_block" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $routing_pattern ]] && record_finding "bank_routing_number" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $account_pattern ]] && record_finding "bank_account_number" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $iban_pattern ]] && record_finding "bank_iban" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $expiry_pattern ]] && record_finding "payment_expiry" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $service_code_pattern ]] && record_finding "payment_service_code" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $masked_card_pattern ]] && record_finding "masked_card" "$file_id" "$line_number" "$view"
  [[ "$lowered" =~ $masked_card_number_pattern ]] && record_finding "masked_card" "$file_id" "$line_number" "$view"
  [[ "$normalized" =~ $track_one_pattern || "$normalized" =~ $track_two_pattern || "$normalized" =~ $track_one_fragment_pattern || "$normalized" =~ $track_two_fragment_pattern || "$lowered" =~ $labelled_track_pattern ]] && record_finding "track_data" "$file_id" "$line_number" "$view"

  if [[ "$lowered" =~ $context_card_pattern && -x /usr/bin/perl ]]; then
    while IFS= read -r candidate; do
      [[ -z "$candidate" ]] && continue
      digits="${candidate//[^0-9]/}"
      if (( ${#digits} >= 12 && ${#digits} <= 19 )); then
        record_finding "payment_card_pan" "$file_id" "$line_number" "$view"
        break
      fi
    done < <(/usr/bin/perl -CS -ne 'while(/(?:card|credit[ _-]+card|debit[ _-]+card|pan|primary[ _-]+account|billing(?:[ _-]+(?:card|account|payment|number))?)[^0-9]{0,32}([0-9][0-9 .\/,"\x27\[\]\(\)+_=-]{10,}[0-9])/ig){print "$1\n"}' <<< "$lowered")
  elif [[ "$lowered" =~ $context_card_pattern && "$lowered" =~ '[0-9]' && ! -x /usr/bin/perl ]]; then
    record_finding "payment_card_context_unparsed" "$file_id" "$line_number" "$view"
  fi

  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    candidates=$((candidates + 1))
    if (( candidates > MAX_FINANCIAL_CANDIDATES_PER_LINE )); then
      record_finding "financial_candidate_limit" "$file_id" "$line_number" "$view"
      break
    fi
    digits="${candidate//[^0-9]/}"
    [[ ${#digits} -ge 12 && ${#digits} -le 19 ]] || continue
    benchmark_line_is_admitted "$line_number" "$view" "$normalized" && continue
    luhn_valid "$digits" || continue
    # Valid-Luhn runs are rejected even without an issuer prefix. Labelled
    # contextual fields above reject invalid check digits as well.
    record_finding "payment_card_pan" "$file_id" "$line_number" "$view"
  done < <(/usr/bin/perl -CS -ne 'while(/([0-9][0-9 .\/,"\x27\[\]\(\)+_=-]{10,}[0-9])/g){print "$1\n"}' <<< "$normalized")
}

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
  scan_financial_value "$value" "$file_id" "$line_number" "$view"
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
  integer decode_depth=${4:-0}
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
    scan_encoded_views "$decoded_line" "$file_id" "$source_line" 0 "$decode_depth"
  done < "$DECODED"
}

scan_encoded_views() {
  local value="$1"
  local file_id="$2"
  local line_number="$3"
  local escaped candidate
  integer candidate_count_ref=$4
  integer decode_depth=${5:-0}

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

  if [[ "$value" =~ '[A-Za-z0-9+/_-]{16}' ]]; then
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
        if (( decode_depth >= 4 )); then
          record_finding "decode_depth" "$file_id" "$line_number" "base64"
        else
          scan_decoded_file "$file_id" "$line_number" "base64" "$((decode_depth + 1))"
        fi
      fi
    done < <(/usr/bin/printf '%s\n' "$value" | /usr/bin/grep -Eo '([A-Za-z0-9+/]{16,}={0,2}|[A-Za-z0-9_-]{16,})' 2>/dev/null || true)
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
  current_relative="$relative"
  current_source_sha256=""
  file_sequence=$((file_sequence + 1))
  file_id="$(/usr/bin/printf 'item-%06d' "$file_sequence")"
  allowlist_reference "$relative" "$file_id"
  file_id="$REPLY"
  financial_tail=""
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
  if (( REPLY > 1 )); then
    record_finding "hardlinked_file" "$file_id" 0 "metadata"
    continue
  fi

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

  source_digest="$(/usr/bin/shasum -a 256 -- "$local_path" 2>/dev/null || true)"
  current_source_sha256="${source_digest%% *}"

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
    current_line_raw="$line"
    if (( ${#line} > MAX_LINE_BYTES )); then
      record_finding "line_too_large" "$file_id" "$line_number" "raw"
      continue
    fi
    if [[ -n "$financial_tail" ]]; then
      # A space keeps the bounded candidate extractor on one line while
      # retaining the fact that the PAN crossed a source-line boundary.
      scan_financial_value "${financial_tail} ${line}" "$file_id" "$line_number" "split"
    fi
    if (( checksum_metadata )); then
      scan_checksum_line "$line" "$file_id" "$line_number" "$base64_candidates"
      base64_candidates="$REPLY"
    else
      scan_text_value "$line" "$file_id" "$line_number" "raw"
      scan_encoded_views "$line" "$file_id" "$line_number" "$base64_candidates"
      base64_candidates="$REPLY"
    fi
    normalize_decimal_digits "$line"
    if (( ${#REPLY} > 64 )); then financial_tail="${REPLY[-64,-1]}"; else financial_tail="$REPLY"; fi
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
