#!/bin/zsh

emulate -LR zsh
set -eu
setopt pipe_fail
export LC_ALL=C
export LANG=C
export TZ=UTC

ROOT="${0:A:h:h}"
SCANNER="$ROOT/scripts/privacy-scan.sh"
TEST_TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/autoassist-financial-test.XXXXXX")"
trap '/bin/rm -rf -- "$TEST_TEMP" 2>/dev/null || true' EXIT INT TERM

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

expect_rejection() {
  local label="$1"
  local directory="$2"
  local expected_rule="$3"
  local output
  if output="$(zsh "$SCANNER" "$directory" 2>&1)"; then
    fail "$label was accepted"
  fi
  [[ "$output" == *"rule=$expected_rule "* ]] || { /usr/bin/printf '%s\n' "$output" >&2; fail "$label did not report the expected rule"; }
  [[ "$output" != *"$directory"* ]] || fail "$label disclosed its fixture path"
  [[ "$output" == *'value=[REDACTED]'* ]] || fail "$label did not redact its finding"
  pass "$label"
}

expect_clean() {
  local label="$1"
  local directory="$2"
  local output
  if ! output="$(zsh "$SCANNER" "$directory" 2>&1)"; then
    /usr/bin/printf '%s\n' "$output" >&2
    fail "$label"
  fi
  [[ "$output" == *'findings=0'* ]] || fail "$label did not report zero findings"
  pass "$label"
}

luhn_valid_fixture() {
  local digits="$1"
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

synthetic_pan() {
  local prefix="$1"
  integer length="$2" digit
  local body="${prefix}"
  while (( ${#body} < length - 1 )); do body+="2"; done
  body="${body[1,$((length - 1))]}"
  for digit in {0..9}; do
    if luhn_valid_fixture "$body$digit"; then REPLY="$body$digit"; return 0; fi
  done
  return 1
}

synthetic_pan 4 16
visa_pan="$REPLY"
synthetic_pan 4 13
visa13_pan="$REPLY"
synthetic_pan 8 16
nonissuer_pan="$REPLY"
invalid_pan="${visa_pan[1,-2]}$(( (10#${visa_pan[-1]} + 1) % 10 ))"

new_case
cvv_fixture="$(printf '1%.0s' {1..3})"
/usr/bin/printf 'CVV: %s\n' "$cvv_fixture" > "$REPLY/input.txt"
expect_rejection 'synthetic CVV' "$REPLY" 'payment_cvv'

new_case
/usr/bin/printf 'PIN=%s\n' '2''4''6''8' > "$REPLY/input.txt"
expect_rejection 'synthetic PIN' "$REPLY" 'payment_pin'

new_case
routing_fixture='3''4''5''6''7''8''9''0''1'
/usr/bin/printf 'routing number: %s\n' "$routing_fixture" > "$REPLY/input.txt"
expect_rejection 'synthetic routing number' "$REPLY" 'bank_routing_number'

new_case
account_fixture='5''6''7''8''9''0''1''2''3''4'
/usr/bin/printf 'bank account number: %s\n' "$account_fixture" > "$REPLY/input.txt"
expect_rejection 'synthetic bank account number' "$REPLY" 'bank_account_number'

new_case
iban_fixture="DE2$(printf '0%.0s' {1..15})"
/usr/bin/printf 'IBAN: %s\n' "$iban_fixture" > "$REPLY/input.txt"
expect_rejection 'synthetic IBAN' "$REPLY" 'bank_iban'

new_case
track_fixture='1''2''3''4'
/usr/bin/printf ';%s=%s?\n' "$visa_pan" "$track_fixture" > "$REPLY/input.txt"
expect_rejection 'synthetic track two data' "$REPLY" 'track_data'

new_case
/usr/bin/printf '%%B%s^SYNTHETIC^%s?\n' "$visa_pan" "$track_fixture" > "$REPLY/input.txt"
expect_rejection 'synthetic track one data' "$REPLY" 'track_data'

new_case
/usr/bin/printf '{"card_number":"%s"}\n' "$invalid_pan" > "$REPLY/input.json"
expect_rejection 'invalid-Luhn contextual card' "$REPLY" 'payment_card_pan'

new_case
/usr/bin/printf '{"cvv":"%s"}\n' '1''2''3' > "$REPLY/input.json"
expect_rejection 'JSON quoted CVV' "$REPLY" 'payment_cvv'

new_case
/usr/bin/printf '{"pin":"%s"}\n' '1''2''3''4' > "$REPLY/input.json"
expect_rejection 'JSON quoted PIN' "$REPLY" 'payment_pin'

new_case
account_json='1''2''3''4''5''6''7''8''9''0'
/usr/bin/printf '{"account_number":"%s"}\n' "$account_json" > "$REPLY/input.json"
expect_rejection 'JSON quoted bank account' "$REPLY" 'bank_account_number'

new_case
/usr/bin/printf '{"expiry_date":"%s"}\n' '1''2/3''4' > "$REPLY/input.json"
expect_rejection 'orphan expiry' "$REPLY" 'payment_expiry'

new_case
/usr/bin/printf '{"payment_token":"%s"}\n' "tok_$(printf 'x1%.0s' {1..8})" > "$REPLY/input.json"
expect_rejection 'payment token' "$REPLY" 'payment_token'

new_case
masked_stars="$(printf '*%.0s' {1..4})"
masked_key='card_number'
/usr/bin/printf '%s: %s %s %s 1234\n' "$masked_key" "$masked_stars" "$masked_stars" "$masked_stars" > "$REPLY/input.txt"
expect_rejection 'masked card fragment' "$REPLY" 'masked_card'

new_case
adjacent="const pan = '${visa13_pan[1,4]}' + '${visa13_pan[5,8]}' + '${visa13_pan[9,-1]}'"
/usr/bin/printf '%s\n' "$adjacent" > "$REPLY/input.js"
expect_rejection 'adjacent literal card fragments' "$REPLY" 'payment_card_pan'

new_case
adjacent_unlabelled="const n = '${visa_pan[1,8]}' + '${visa_pan[9,-1]}'"
/usr/bin/printf '%s\n' "$adjacent_unlabelled" > "$REPLY/input.js"
expect_rejection 'unlabelled adjacent literal card fragments' "$REPLY" 'payment_card_pan'

new_case
digit_array=""
for ((index=1; index<=${#visa13_pan}; index++)); do
  [[ -n "$digit_array" ]] && digit_array+=","
  digit_array+="${visa13_pan[index]}"
done
/usr/bin/printf '{"pan":[%s]}\n' "$digit_array" > "$REPLY/input.json"
expect_rejection 'numeric digit array' "$REPLY" 'payment_card_pan'

new_case
/usr/bin/printf '%s\n' "${visa13_pan[1,4]}.${visa13_pan[5,8]}.${visa13_pan[9,-1]}" > "$REPLY/input.txt"
expect_rejection 'dotted PAN' "$REPLY" 'payment_card_pan'

new_case
/usr/bin/printf '%s\n' "${visa13_pan[1,4]}/${visa13_pan[5,8]}/${visa13_pan[9,-1]}" > "$REPLY/input.txt"
expect_rejection 'slashed PAN' "$REPLY" 'payment_card_pan'

new_case
entity_pan=""
for ((index=1; index<=${#visa13_pan}; index++)); do
  entity_pan+="&#$((10#${visa13_pan[index]} + 48));"
done
/usr/bin/printf '%s\n' "$entity_pan" > "$REPLY/input.txt"
expect_rejection 'HTML numeric entities' "$REPLY" 'payment_card_pan'

new_case
short_base64="$(/usr/bin/printf '%s' "$visa13_pan" | /usr/bin/base64 | /usr/bin/tr -d '\n')"
/usr/bin/printf '%s\n' "$short_base64" > "$REPLY/input.txt"
expect_rejection 'short Base64 PAN' "$REPLY" 'payment_card_pan'

new_case
nested_base64="$(/usr/bin/printf '%s' "$short_base64" | /usr/bin/base64 | /usr/bin/tr -d '\n')"
/usr/bin/printf '%s\n' "$nested_base64" > "$REPLY/input.txt"
expect_rejection 'nested short Base64 PAN' "$REPLY" 'payment_card_pan'

new_case
/usr/bin/printf '{"cid":"%s"}\n' '1''2''3''4' > "$REPLY/input.json"
expect_rejection 'CID without PAN' "$REPLY" 'payment_cvv'

new_case
pin_block_value="ABCDEF$(printf '1%.0s' {1..10})"
/usr/bin/printf '{"pin_block":"%s"}\n' "$pin_block_value" > "$REPLY/input.json"
expect_rejection 'PIN block without PAN' "$REPLY" 'pin_block'

new_case
/usr/bin/printf '{"billing":"%s"}\n' "$invalid_pan" > "$REPLY/input.json"
expect_rejection 'billing card field' "$REPLY" 'payment_card_pan'

new_case
billing_key='billing_address'
billing_value='Synthetic Example'
/usr/bin/printf '%s: "%s"\n' "$billing_key" "$billing_value" > "$REPLY/input.txt"
expect_rejection 'populated billing address' "$REPLY" 'billing_field'

new_case
/usr/bin/printf 'track2: %s=\n' "${visa_pan[-4,-1]}" > "$REPLY/input.txt"
expect_rejection 'labelled track2 fragment' "$REPLY" 'track_data'

new_case
/usr/bin/printf '%s\n' "$nonissuer_pan" > "$REPLY/input.txt"
expect_rejection 'nonissuer valid-Luhn PAN' "$REPLY" 'payment_card_pan'

new_case
token_key='payment_token'
opaque_token="opaque$(printf 'value%.0s' {1..4})"
/usr/bin/printf '%s: REDACTED\n%s: %s\n' "$token_key" "$token_key" "$opaque_token" > "$REPLY/input.txt"
expect_rejection 'placeholder token does not suppress populated token' "$REPLY" 'payment_token'

new_case
/usr/bin/printf '%s: abcd\n' "$token_key" > "$REPLY/input.txt"
expect_rejection 'short populated payment token' "$REPLY" 'payment_token'

new_case
cardholder_key='cardholder_name'
/usr/bin/printf '%s: "Synthetic Example"\n' "$cardholder_key" > "$REPLY/input.txt"
expect_rejection 'populated cardholder name' "$REPLY" 'cardholder_name'

new_case
cvn_key='cvn2'
/usr/bin/printf '%s: 123\n' "$cvn_key" > "$REPLY/input.txt"
expect_rejection 'CVN2 field' "$REPLY" 'payment_cvv'

new_case
service_key='service_code'
/usr/bin/printf '%s: 123\n' "$service_key" > "$REPLY/input.txt"
expect_rejection 'service code field' "$REPLY" 'payment_service_code'

new_case
/usr/bin/printf '%%B%s\n' "$(printf '4%.0s' {1..12})" > "$REPLY/input.txt"
expect_rejection 'track data fragment' "$REPLY" 'track_data'

new_case
/usr/bin/printf '{"cvv":"","pin":"REDACTED","card_number":"REDACTED","payment_token":"placeholder"}\n' > "$REPLY/input.json"
expect_clean 'empty and placeholder financial fields' "$REPLY"

new_case
unicode_pan="$(/usr/bin/perl -Mutf8 -CS -e 'my $x=shift; $x =~ s/([0-9])/chr(0x660+$1)/ge; print $x' "$visa_pan")"
/usr/bin/printf '%s\n' "$unicode_pan" > "$REPLY/input.txt"
expect_rejection 'Unicode-digit PAN' "$REPLY" 'payment_card_pan'

new_case
/usr/bin/printf '%s\n%s\n' "${visa_pan[1,8]}" "${visa_pan[9,-1]}" > "$REPLY/input.txt"
expect_rejection 'split PAN across lines' "$REPLY" 'payment_card_pan'

new_case
/bin/mkdir -p "$REPLY/benchmarks/osworld-2.0"
benchmark_one="$(printf '1%.0s' {1..16})"
benchmark_two="$(printf '7%.0s' {1..15})1"
/usr/bin/printf 'score=0.%s, reward=0.%s\n' "$benchmark_one" "$benchmark_two" > "$REPLY/benchmarks/osworld-2.0/results.csv"
expect_rejection 'unproven benchmark numeric controls' "$REPLY" 'payment_card_pan'

new_case
/bin/mkdir -p "$REPLY/benchmarks/osworld-2.0"
/bin/cp -- "$ROOT/benchmarks/osworld-2.0/results.csv" "$REPLY/benchmarks/osworld-2.0/results.csv"
expect_clean 'exact public benchmark numeric controls' "$REPLY"

new_case
/bin/mkdir -p "$REPLY/benchmarks/osworld-2.0"
/usr/bin/printf '%s\n' "$visa_pan" > "$REPLY/benchmarks/osworld-2.0/results.csv"
expect_rejection 'unlabelled benchmark PAN-shaped control' "$REPLY" 'payment_card_pan'

new_case
/bin/mkdir -p "$REPLY/benchmarks/osworld-2.0"
/usr/bin/printf 'card: %s\n' "$visa_pan" > "$REPLY/benchmarks/osworld-2.0/results.csv"
expect_rejection 'labelled benchmark PAN' "$REPLY" 'payment_card_pan'

new_case
/usr/bin/printf '\211PNG\015\012\032\012' > "$REPLY/art.png"
expect_rejection 'unsupported opaque media' "$REPLY" 'opaque_media'

new_case
/usr/bin/printf 'PK\003\004synthetic archive marker\n' > "$REPLY/art.txt"
expect_rejection 'unsupported opaque archive' "$REPLY" 'archive_zip'

node --test "$ROOT/tests/test-publication-scan.mjs"
/usr/bin/printf 'Privacy detector tests passed: %d assertions plus publication scanner tests.\n' "$assertions"
