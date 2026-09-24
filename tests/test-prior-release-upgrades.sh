#!/bin/zsh
set -eu
umask 077

SOURCE_ROOT="${0:A:h:h}"
CURRENT_VERSION="$(/bin/cat "$SOURCE_ROOT/VERSION")"
[[ "$CURRENT_VERSION" == 0.4.0 ]] || { /bin/echo 'expected candidate v0.4.0' >&2; exit 1; }

for prior in 0.2.0 0.3.0; do
  zip_var="AUTOASSIST_V${prior//./}_ZIP"
  PRIOR_ZIP="${(P)zip_var:-}"
  [[ "$PRIOR_ZIP" == /* && -f "$PRIOR_ZIP" && ! -L "$PRIOR_ZIP" ]] || { /bin/echo "missing exact public v$prior ZIP" >&2; exit 2; }
  case "$prior" in
    0.2.0) expected=e960777bf34cdb96b18af16feb37973c4cf4db939df91e837841f71e1eedb144 ;;
    0.3.0) expected=f276fe82f549e2639eeecabbb66323971ab9ff4606029b6ca5fb89dd3fde59bb ;;
  esac
  [[ "$(/usr/bin/shasum -a 256 "$PRIOR_ZIP" | /usr/bin/awk '{print $1}')" == "$expected" ]] || { /bin/echo "public v$prior ZIP hash mismatch" >&2; exit 1; }

  test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/autobot-prior-upgrade.XXXXXX")"
  test_root="${test_root:A}"
  account_home="$test_root/Test User"
  destination="$account_home/AutoAssist"
  /bin/mkdir -p "$account_home" "$test_root/extracted"
  /usr/bin/ditto -x -k "$PRIOR_ZIP" "$test_root/extracted"
  prior_source="$test_root/extracted/AutoAssist"
  [[ -f "$prior_source/install.sh" ]] || { /bin/echo "public v$prior source missing installer" >&2; exit 1; }
  /bin/chmod +x "$prior_source/install.sh"
  AUTOASSIST_TEST_NODE_ABSENT=1 "$prior_source/install.sh" --home-root "$account_home" --destination "$destination" --instance-id "prior${prior//./}" --skip-launch-agent --test-mode --test-root "$test_root" > "$test_root/old-install.log"
  [[ "$(/bin/cat "$destination/VERSION")" == "$prior" ]] || { /bin/echo "public v$prior install failed" >&2; exit 1; }

  /usr/bin/printf '\nSynthetic user instruction remains owned by the user.\n' >> "$destination/AGENTS.md"
  /bin/mkdir -p "$destination/01_PROJECTS/my-project" "$destination/state"
  /usr/bin/printf 'synthetic project state\n' > "$destination/01_PROJECTS/my-project/data.txt"
  /usr/bin/printf 'synthetic runtime state\n' > "$destination/state/custom-user-data.txt"
  agent_hash="$(/usr/bin/shasum -a 256 "$destination/AGENTS.md" | /usr/bin/awk '{print $1}')"
  project_hash="$(/usr/bin/shasum -a 256 "$destination/01_PROJECTS/my-project/data.txt" | /usr/bin/awk '{print $1}')"
  state_hash="$(/usr/bin/shasum -a 256 "$destination/state/custom-user-data.txt" | /usr/bin/awk '{print $1}')"

  AUTOASSIST_TEST_NODE_ABSENT=1 "$SOURCE_ROOT/install.sh" --home-root "$account_home" --destination "$destination" --instance-id "prior${prior//./}" --skip-launch-agent --target-quiescent --test-mode --test-root "$test_root" > "$test_root/new-install.log"
  [[ "$(/bin/cat "$destination/VERSION")" == "$CURRENT_VERSION" ]] || { /bin/echo "v$prior upgrade did not install current version" >&2; exit 1; }
  [[ "$agent_hash" == "$(/usr/bin/shasum -a 256 "$destination/AGENTS.md" | /usr/bin/awk '{print $1}')" ]] || { /bin/echo "v$prior user instructions changed" >&2; exit 1; }
  [[ "$project_hash" == "$(/usr/bin/shasum -a 256 "$destination/01_PROJECTS/my-project/data.txt" | /usr/bin/awk '{print $1}')" ]] || { /bin/echo "v$prior project data changed" >&2; exit 1; }
  [[ "$state_hash" == "$(/usr/bin/shasum -a 256 "$destination/state/custom-user-data.txt" | /usr/bin/awk '{print $1}')" ]] || { /bin/echo "v$prior runtime state changed" >&2; exit 1; }
  [[ -f "$destination/INSTALL_FOR_AI.md" && -f "$destination/docs/benchmark-charts/assistantbench-highlighted.png" ]] || { /bin/echo "v$prior upgrade missed newly shipped files" >&2; exit 1; }
  AUTOASSIST_ACCOUNT_HOME="$account_home" "$destination/runtime/bin/autoassist" doctor --json > "$test_root/new-doctor.json"
  /bin/echo "Exact public v$prior upgrade preserved synthetic instructions, project data and runtime state."
  /bin/rm -rf "$test_root"
done
