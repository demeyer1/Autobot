#!/bin/zsh

# Shared, Node-free lifecycle helpers. Callers set -eu and umask 077.

aa_die() {
  /bin/echo "AutoAssist: $*" >&2
  exit 1
}

aa_usage_die() {
  /bin/echo "AutoAssist: $*" >&2
  exit 2
}

aa_sha256() {
  /usr/bin/shasum -a 256 -- "$1" | /usr/bin/awk '{print $1}'
}

aa_safe_token() {
  [[ "$1" =~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' ]]
}

aa_safe_absolute_path() {
  local path="$1"
  [[ -n "$path" && "$path" == /* && "$path" != "/" && "$path" != *$'\n'* \
    && "$path" != *'//'* && "$path" != *'/../'* && "$path" != */.. \
    && "$path" != *'/./'* && "$path" != */. \
    && "$path" =~ '^[A-Za-z0-9._/ -]+$' ]]
}

aa_reject_symlink_components() {
  local path="$1"
  local cursor="/"
  local component
  local -a components
  components=("${(@s:/:)${path#/}}")
  for component in "${components[@]}"; do
    [[ -z "$component" ]] && continue
    if [[ "$cursor" == "/" ]]; then cursor="/$component"; else cursor="$cursor/$component"; fi
    [[ -L "$cursor" ]] && aa_die "refusing path with symlink component: $cursor"
  done
}

aa_require_child() {
  local child="$1"
  local parent="$2"
  [[ "$child" == "$parent"/* ]] || aa_usage_die "destination must be a child of the selected account home"
}

aa_require_owned_directory() {
  local path="$1"
  local boundary="${2:-$path}"
  aa_safe_absolute_path "$path" || aa_die "unsafe ancillary directory: $path"
  aa_safe_absolute_path "$boundary" || aa_die "unsafe ancillary boundary: $boundary"
  [[ "$path" == "$boundary" || "$path" == "$boundary"/* ]] || aa_die "ancillary directory escapes its ownership boundary"
  aa_reject_symlink_components "$path"
  if [[ ! -e "$path" ]]; then /bin/mkdir -p -- "$path"; fi
  [[ -d "$path" && ! -L "$path" ]] || aa_die "ancillary path is not a real directory: $path"
  aa_check_owned_ancestors "$path" "$boundary"
}

aa_check_owned_ancestors() {
  local path="$1"
  local boundary="$2"
  aa_reject_symlink_components "$path"
  [[ "$path" == "$boundary" || "$path" == "$boundary"/* ]] || aa_die "ancillary path escapes its ownership boundary"
  local cursor="$boundary"
  [[ "$(/usr/bin/stat -f '%u' "$cursor")" == "$(/usr/bin/id -u)" ]] || aa_die "ancillary boundary owner mismatch: $cursor"
  local relative="${path#$boundary/}"
  local component
  local -a components
  components=("${(@s:/:)relative}")
  for component in "${components[@]}"; do
    [[ -z "$component" ]] && continue
    cursor="$cursor/$component"
    [[ -e "$cursor" ]] || break
    [[ "$(/usr/bin/stat -f '%u' "$cursor")" == "$(/usr/bin/id -u)" ]] || aa_die "ancillary path owner mismatch: $cursor"
  done
}

aa_safe_manifest_entry() {
  local entry="$1"
  [[ -n "$entry" && "$entry" != /* && "$entry" != *$'\n'* \
    && "$entry" != .. && "$entry" != ../* && "$entry" != */../* && "$entry" != */.. \
    && "$entry" != . && "$entry" != ./* && "$entry" != */./* && "$entry" != */. ]]
}

aa_manifest_lines() {
  /usr/bin/awk 'NF && $1 !~ /^#/ { print }' "$1"
}

aa_manifest_contains() {
  /usr/bin/awk -v value="$2" '$0 == value { found=1 } END { exit found ? 0 : 1 }' "$1"
}

aa_is_seed() {
  aa_manifest_contains "$1" "$2"
}

aa_validate_release_manifest() {
  local root="$1"
  local manifest="$2"
  [[ -f "$manifest" && ! -L "$manifest" ]] || aa_die "release allowlist is missing"
  local prior=""
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    aa_safe_manifest_entry "$entry" || aa_die "unsafe release allowlist entry: $entry"
    if [[ "$entry" == benchmarks/* ]]; then
      case "$entry" in
        benchmarks/assistantbench/README.md|benchmarks/assistantbench/leaderboard.png|benchmarks/osworld-2.0/README.md|benchmarks/osworld-2.0/SHA256SUMS|benchmarks/osworld-2.0/leaderboard-comparison.jpg|benchmarks/osworld-2.0/results.csv|benchmarks/osworld-2.0/score-evidence.json|benchmarks/osworld-2.0/summary.json|benchmarks/osworld-2.0/verify.py) ;;
        *) aa_die "non-passive benchmark material is forbidden: $entry" ;;
      esac
    fi
    [[ -z "$prior" || "$entry" > "$prior" ]] || aa_die "release allowlist must be sorted and unique"
    prior="$entry"
    [[ -f "$root/$entry" && ! -L "$root/$entry" ]] || aa_die "release entry must be a regular file: $entry"
  done < "$manifest"
}

aa_tree_has_unsafe_nodes() {
  local root="$1"
  [[ -d "$root" && ! -L "$root" ]] || return 0
  /usr/bin/find -P "$root" \( -type l -o \( ! -type d ! -type f \) \) -print -quit | /usr/bin/grep -q .
}

aa_tree_digest() {
  local root="$1"
  local excluded="${2:-}"
  [[ -d "$root" && ! -L "$root" ]] || return 1
  aa_tree_has_unsafe_nodes "$root" && return 1
  (
    cd "$root"
    /usr/bin/find -P . -type f -print | LC_ALL=C /usr/bin/sort | while IFS= read -r path; do
      path="${path#./}"
      [[ -n "$excluded" && "$path" == "$excluded" ]] && continue
      /usr/bin/printf '%s %s\n' "$(aa_sha256 "$root/$path")" "$path"
    done
  ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

aa_plist_is_owned() {
  local plist="$1"
  local label="$2"
  local root="$3"
  [[ -f "$plist" && ! -L "$plist" ]] \
    && /usr/bin/grep -F -q "<string>$label</string>" "$plist" \
    && /usr/bin/grep -F -q "<string>$root/runtime/bin/autoassist</string>" "$plist"
}

aa_service_is_absent() {
  ! /bin/launchctl print "gui/$(/usr/bin/id -u)/$1" >/dev/null 2>&1
}

aa_service_targets_root() {
  local label="$1"
  local root="$2"
  /bin/launchctl print "gui/$(/usr/bin/id -u)/$label" 2>/dev/null | /usr/bin/grep -F -q "$root/runtime/bin/autoassist"
}

aa_stop_owned_service() {
  local label="$1"
  local root="$2"
  if aa_service_is_absent "$label"; then return 0; fi
  aa_service_targets_root "$label" "$root" || return 1
  /bin/launchctl bootout "gui/$(/usr/bin/id -u)/$label" >/dev/null 2>&1 || return 1
  aa_service_is_absent "$label"
}

aa_copy_file() {
  local source="$1"
  local destination="$2"
  [[ -f "$source" && ! -L "$source" ]] || aa_die "source is not a regular file: $source"
  /bin/mkdir -p -- "${destination:h}"
  /bin/cp -p -- "$source" "$destination"
}

aa_manifest_hash_for() {
  local manifest="$1"
  local entry="$2"
  [[ -f "$manifest" ]] || return 1
  /usr/bin/awk -v path="$entry" 'substr($0,67) == path { print substr($0,1,64); found=1; exit } END { exit found ? 0 : 1 }' "$manifest"
}

aa_generate_manifest() {
  local root="$1"
  local allowlist="$2"
  local output="$3"
  local temp="$output.tmp.$$"
  : > "$temp"
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    /usr/bin/printf '%s  %s\n' "$(aa_sha256 "$root/$entry")" "$entry" >> "$temp"
  done < "$allowlist"
  /bin/chmod 600 "$temp"
  /bin/mv -f -- "$temp" "$output"
}

aa_legacy_manifest() {
  local output="$1"
  /bin/cat > "$output" <<'EOF'
52d0652d1f2d62fd9f762c62879c6c09c29c2c2229218a0013c545bf2e55d73d  .gitignore
d86b3c7c5bdef947f69f651e6aaff5aa723d0d35a64ecafca124b0b60c701dde  00_CONTEXT/COMMUNICATION-PROFILES.md
2a20b3d28840767462ff9aa532cc25c09c55dfe56e32213eae9eb41708b46826  00_CONTEXT/ISSUES/README.md
1c2d4f7e213c4c02f3b9e8c333a23089c93584660825fa8f478552e9118355d8  00_CONTEXT/ISSUES/issues.json
feafd6778a8fdceac8905dbf75daa8441ae402ae8a1c6f4276a82a14b6175bb8  00_CONTEXT/MEMORY.md
5edd9a1be33df97bb5180b78b2b3aec4e050853636373a4b35829322526d45ef  00_CONTEXT/OUTBOUND-ACTION-POLICY.md
1c1290d767af3cb3171d59cca462c81c2617b416b04299fc3c59807270670d1b  00_CONTEXT/PRIVACY-ZONES.md
e2a5c204c66ecfb15bcf779f15bfab53e014d45564f0035ea1083cf8228199f7  01_PROJECTS/_template/STATUS.md
b30d4041318ac930034db1626ad20639d52f942c93318458df84f20210b5d095  02_INBOX/README.md
d992e41077f6f1d31ef5fbfd5e638528a9b012035fc7bc88954d6102702df27f  03_OUTPUTS/README.md
aa22ed01afaede966f0913a6af5facc8ece9d7b3ba6be5ac32be3f1ba16bbd78  AGENTS.md
f2575103368bc7d5a5e92b669cdae34ccbe49d27589d52e03cf456515d8d2949  Install.command
a8323253d2ae9e1eb82372f057ecb64f7f9892bcb2e53db758e7097e2da1270b  LICENSE
f447b8283013cb1d77d1672a1c83f0a2df82e2b4c13e37c7879a7ce3a306c5cd  PRIVACY.md
6db66f5075bca3a0b7ee1662500bc4d3fe8615c0eb0e62895550f117569640c1  PROJECTS.md
8d89fd6df61a852562048903a059954288b5c439f35997dcbe4206ec88993a3a  README.md
0756ce90e1a8896b4c19c51cc324392a3b596283c7a2fbbced634f761ba31ea1  SECURITY.md
9ca90d4ac8fbe86d8aca4aa37a80e0f984c01df281f25f62c779e784fd155a21  VERSION
3b294d3e66fc7abae021a7ff1ef57ca37d36893b55e206c68a5f630013791b27  config/immutable-manifest.txt
6fb14a4ead6d9aa7be14fdb648ec0ae3e6be6e97c9cb2900b12beedc65d63873  config/profile.example.conf
7c435eec87b455be27c3190633ab55e4ed23a97740816383dc81fdf8ce5b4832  config/release-allowlist.txt
44c9d609e80210963b9f23e78d5bba77c88c70bacaeefb24e332fb287f19564d  config/seed-manifest.txt
b0f55f8aed6b4676e983230b33d0a05629c64d9efeee92c26009d57a27481bc4  docs/ARCHITECTURE.md
1e820fb73b3cd593881cf340895bd2fc79567ce09495b1f9512b7ec009c8bb48  docs/COMPARISON.md
b298850016697bc776c8b0a5b0d958879832ec3910894e896572abc5de3a52c9  docs/INSTALL.md
97f0fae480bb2cf1240d0755e14066ea842f2226fbcbb8f7dcf858155311fc31  docs/PERMISSIONS.md
f639ba1ac90731f92c9e2c5ceb5cf2e98d75ad4199dd497a0cb78abbdd4d0f0f  docs/TROUBLESHOOTING.md
70baa082205a68ce11c9f5f21e3ea0b2c687f3ccb5b4d536098c1f8f90419ab8  install.sh
a6274aaaa614d23510afe53cb037baec2b1ce3198986ed83505c616a845e7584  runtime/bin/autoassist
cef2b76829ffa3dfe150e55b7406d1984227c9ed210f32162ac51b85880e3b1c  runtime/lib/common.sh
d3c2f493c0df9fac48effd59f434b576f1ce67b2fe2c8b6ed287e6c35ed81302  runtime/templates/io.autoassist.supervisor.plist.template
dd8ed7d1f10f6c11fd1a38c5f6e406d78c62f88b7875292b600aa9bbbb605a91  scripts/package.sh
6ab19fdc822349244aa48af851fb036cf2bbec1f716a2cbe98026a60a170d32c  scripts/privacy-scan.sh
63b9cbb315adde7a632ed60d1aef20ccadee35f060d4fac41ea0930b34291223  scripts/verify-release.sh
aea980e17104f0f177e9990f24f4abb26b6ca05e15e6c26749addb9f07b72a9a  skills/first-time/SKILL.md
65c763398c66724641df4150cefa256940e11ae9bb44f062419ae708dd8c57ac  skills/first-time/agents/openai.yaml
e91db3a3830f93b166b756f6b42ca2ef3524efd93740030de6ecdad57f974d12  skills/first-time/references/configuration.md
825ee06b1bec44bb0403613bcc6f043ea7a49715cbf7d18bfb4366b06d5855eb  skills/first-time/references/macos-and-sign-in.md
02a9ca7052cc48b1d6ab0bff901e71cf6ea9a0660963997a8b3e7daf6d6cd97b  skills/first-time/references/privacy-and-communications.md
7b8bb07d40be6ebd2f61dfd1d4a14abb6904c35714ccff8c82ad87d55bdf2f81  skills/first-time/references/setup-workflow.md
680cc17c5057bcc64e078468d4a5a347b060148bf3a0df63374ab4ba142316df  skills/first-time/scripts/validate-setup.sh
af3e26cc701de7e17a55c5e668a97c2a2b258439a9ab7587d947fd872e527acd  skills/first-time/scripts/write-status.sh
e5f53242f5394f1cd2f5c6647edcc91e8f398df9715b7f0004a21ece01f5bdcc  tests/run-all.sh
a46e8f7cf3b88efe65667a12b50dd33b5986de97ee163cf15c47dee85f9325b1  tests/test-first-time-status.sh
252deb3d4377db86fc32525dd031c8482b69f915d49faa0d73bb17ec9f7f87a8  tests/test-install.sh
87b9234fcf8a6eb97547363bc96f102cc637debe1590a61868225f0f74f92227  tests/test-privacy-scan.sh
6ba0ef4586f0f0b0049c5c1bccc80321e0061b39a1eebc6f636c93691748c73e  tests/test-runtime.sh
48630dcfc94b1d0a0c1210fd1a6b6035a2956109a7e39e01f2d90d8f52591c16  uninstall.sh
EOF
  /bin/chmod 600 "$output"
}

aa_discover_node() {
  local root="$1"
  AA_NODE_PATH=""
  AA_NODE_VERSION=""
  AA_NODE_STATUS="unavailable"
  if [[ "${AUTOASSIST_TEST_NODE_ABSENT:-0}" == "1" ]]; then return 0; fi
  local candidate=""
  local explicit=0
  if [[ "${AUTOASSIST_NODE+x}" == x ]]; then
    explicit=1
    candidate="$AUTOASSIST_NODE"
  elif [[ -f "$root/.install-state/receipt.json" && ! -L "$root/.install-state/receipt.json" ]]; then
    candidate="$(/usr/bin/plutil -extract node_path raw -o - "$root/.install-state/receipt.json" 2>/dev/null || true)"
  fi
  if [[ "$explicit" -eq 0 && -z "$candidate" ]]; then
    candidate="$(command -v node 2>/dev/null || true)"
  fi
  [[ -n "$candidate" && "$candidate" == /* && -e "$candidate" && -x "$candidate" ]] || return 0
  candidate="${candidate:A}"
  [[ "$candidate" == /* && -f "$candidate" && -x "$candidate" && ! -L "$candidate" ]] || return 0
  local version
  version="$($candidate --version 2>/dev/null || true)"
  local major="${${version#v}%%.*}"
  [[ "$major" == <-> && "$major" -ge 22 ]] || { AA_NODE_STATUS="unsupported"; AA_NODE_PATH="$candidate"; AA_NODE_VERSION="$version"; return 0; }
  AA_NODE_STATUS="available"
  AA_NODE_PATH="$candidate"
  AA_NODE_VERSION="$version"
}

aa_json_escape() {
  /usr/bin/printf '%s' "$1" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g'
}
