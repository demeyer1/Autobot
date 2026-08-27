#!/bin/zsh

set -eu

AUTOASSIST_HELD_LOCK=""
AUTOASSIST_HELD_LOCK_TOKEN=""

autoassist_now_iso() {
  /bin/date -u "+%Y-%m-%dT%H:%M:%SZ"
}

autoassist_now_epoch() {
  /bin/date "+%s"
}

autoassist_fail() {
  /bin/echo "AutoAssist: $*" >&2
  return 1
}

autoassist_atomic_write() {
  local target="$1"
  local value="$2"
  local parent
  local temporary
  parent="${target:h}"
  /bin/mkdir -p "$parent"
  temporary="${parent}/.${target:t}.tmp.$$"
  /usr/bin/printf '%s\n' "$value" > "$temporary"
  /bin/chmod 600 "$temporary"
  /bin/mv -f "$temporary" "$target"
}

autoassist_validate_id() {
  local value="$1"
  if [[ ! "$value" =~ '^[a-z0-9][a-z0-9-]{2,63}$' ]]; then
    autoassist_fail "identifier must use 3-64 lowercase letters, digits, or hyphens"
  fi
}

autoassist_validate_actor() {
  local value="$1"
  if [[ ! "$value" =~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{1,127}$' ]]; then
    autoassist_fail "actor identity has an invalid format"
  fi
}

autoassist_stage_number() {
  case "$1" in
    research_complete) /usr/bin/printf '1\n' ;;
    draft_complete) /usr/bin/printf '2\n' ;;
    destination_updated) /usr/bin/printf '3\n' ;;
    save_confirmed) /usr/bin/printf '4\n' ;;
    rendered_readback_verified) /usr/bin/printf '5\n' ;;
    *) return 1 ;;
  esac
}

autoassist_previous_stage() {
  case "$1" in
    research_complete) /usr/bin/printf '\n' ;;
    draft_complete) /usr/bin/printf 'research_complete\n' ;;
    destination_updated) /usr/bin/printf 'draft_complete\n' ;;
    save_confirmed) /usr/bin/printf 'destination_updated\n' ;;
    rendered_readback_verified) /usr/bin/printf 'save_confirmed\n' ;;
    *) return 1 ;;
  esac
}

autoassist_sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

autoassist_acquire_lock() {
  local lock_path="$1"
  if ! /bin/mkdir "$lock_path" 2>/dev/null; then
    autoassist_fail "state is locked by another process: $lock_path"
  fi
  local token
  token="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
  if ! autoassist_atomic_write "$lock_path/owner" "pid=$$ token=$token captured_at=$(autoassist_now_iso)"; then
    /bin/rmdir "$lock_path" 2>/dev/null || true
    autoassist_fail "could not persist lock ownership: $lock_path"
  fi
  AUTOASSIST_HELD_LOCK="$lock_path"
  AUTOASSIST_HELD_LOCK_TOKEN="$token"
}

autoassist_release_lock() {
  local lock_path="$1"
  local expected_token="$2"
  local owner_file="$lock_path/owner"
  if [[ ! -f "$owner_file" || -L "$owner_file" ]]; then
    autoassist_fail "cannot verify lock ownership for release: $lock_path"
    return 1
  fi
  local owner
  owner="$(/bin/cat "$owner_file")"
  if [[ "$owner" != "pid=$$ token=$expected_token "* ]]; then
    autoassist_fail "lock ownership changed before release: $lock_path"
    return 1
  fi
  /bin/rm -f "$owner_file"
  if ! /bin/rmdir "$lock_path" 2>/dev/null; then
    autoassist_fail "lock directory is not empty during release: $lock_path"
    return 1
  fi
}

autoassist_release_held_lock() {
  if [[ -z "$AUTOASSIST_HELD_LOCK" ]]; then
    return 0
  fi
  local held_lock="$AUTOASSIST_HELD_LOCK"
  local held_token="$AUTOASSIST_HELD_LOCK_TOKEN"
  AUTOASSIST_HELD_LOCK=""
  AUTOASSIST_HELD_LOCK_TOKEN=""
  if ! autoassist_release_lock "$held_lock" "$held_token"; then
    /bin/echo "AutoAssist: failed to release owned lock: $held_lock" >&2
    return 1
  fi
}
