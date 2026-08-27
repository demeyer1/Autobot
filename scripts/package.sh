#!/bin/zsh

set -eu

ROOT="${0:A:h:h}"
VERSION="$(<"$ROOT/VERSION")"
DIST="$ROOT/dist"
ARCHIVE="$DIST/AutoAssist-v${VERSION}.zip"
CHECKSUM="$ARCHIVE.sha256"
TREE_MANIFEST="$DIST/AutoAssist-v${VERSION}.manifest.sha256"

AUTOASSIST_PACKAGE_PARENT=1 "$ROOT/tests/run-all.sh"

PACKAGE_TEMP="$(/usr/bin/mktemp -d -t autoassist-package)"
trap '/bin/rm -rf "$PACKAGE_TEMP"' EXIT INT TERM
PACKAGE_ROOT="$PACKAGE_TEMP/AutoAssist"
UNPACK_ROOT="$PACKAGE_TEMP/unpacked"
EXPECTED_PATHS="$PACKAGE_TEMP/expected-paths.txt"
OBSERVED_PATHS="$PACKAGE_TEMP/observed-paths.txt"
SOURCE_TREE_HASHES="$PACKAGE_TEMP/source-tree.sha256"
UNPACKED_TREE_HASHES="$PACKAGE_TEMP/unpacked-tree.sha256"
METADATA_ROOT="$PACKAGE_TEMP/release-metadata"
/bin/mkdir -p "$PACKAGE_ROOT"

while IFS= read -r entry; do
  [[ -z "$entry" || "$entry" == \#* ]] && continue
  if [[ "$entry" == /* || "$entry" == *'..'* || "$entry" == *$'\n'* ]]; then
    /bin/echo "Unsafe package allowlist entry: $entry" >&2
    exit 2
  fi
  if [[ ! -f "$ROOT/$entry" || -L "$ROOT/$entry" ]]; then
    /bin/echo "Package allowlist entry is missing: $entry" >&2
    exit 2
  fi
  /bin/mkdir -p "$PACKAGE_ROOT/${entry:h}"
  /bin/cp -p "$ROOT/$entry" "$PACKAGE_ROOT/$entry"
  /usr/bin/printf '%s\n' "$entry" >> "$EXPECTED_PATHS"
done < "$ROOT/config/release-allowlist.txt"

LC_ALL=C /usr/bin/sort -u "$EXPECTED_PATHS" -o "$EXPECTED_PATHS"
(
  cd "$PACKAGE_ROOT"
  /usr/bin/find . -type f -print | /usr/bin/sed 's|^\./||' | LC_ALL=C /usr/bin/sort > "$OBSERVED_PATHS"
)
if ! /usr/bin/cmp -s "$EXPECTED_PATHS" "$OBSERVED_PATHS"; then
  /bin/echo "Packaged path set does not exactly match the release allowlist." >&2
  /usr/bin/diff -u "$EXPECTED_PATHS" "$OBSERVED_PATHS" >&2 || true
  exit 2
fi

"$PACKAGE_ROOT/scripts/privacy-scan.sh" "$PACKAGE_ROOT"
(
  cd "$PACKAGE_ROOT"
  while IFS= read -r relative; do
    /usr/bin/shasum -a 256 "$relative"
  done < "$EXPECTED_PATHS"
) > "$SOURCE_TREE_HASHES"
/bin/mkdir -p "$DIST"
/bin/rm -f "$ARCHIVE" "$CHECKSUM" "$TREE_MANIFEST"
/usr/bin/ditto -c -k --norsrc --keepParent "$PACKAGE_ROOT" "$ARCHIVE"

LISTING="$(/usr/bin/unzip -Z1 "$ARCHIVE")"
if /usr/bin/printf '%s\n' "$LISTING" | /usr/bin/grep -q '^__MACOSX/'; then
  /bin/echo "Archive contains __MACOSX metadata." >&2
  exit 3
fi
if /usr/bin/printf '%s\n' "$LISTING" | /usr/bin/grep -q '\.\./'; then
  /bin/echo "Archive contains a parent traversal entry." >&2
  exit 3
fi
if /usr/bin/printf '%s\n' "$LISTING" | /usr/bin/grep -q '^/'; then
  /bin/echo "Archive contains an absolute entry." >&2
  exit 3
fi

/bin/mkdir -p "$UNPACK_ROOT"
/usr/bin/ditto -x -k "$ARCHIVE" "$UNPACK_ROOT"
UNPACKED_ROOT="$UNPACK_ROOT/AutoAssist"
if [[ ! -d "$UNPACKED_ROOT" ]]; then
  /bin/echo "Archive did not unpack to one AutoAssist root." >&2
  exit 3
fi
"$UNPACKED_ROOT/scripts/privacy-scan.sh" "$UNPACKED_ROOT"
(
  cd "$UNPACKED_ROOT"
  while IFS= read -r relative; do
    if [[ ! -f "$relative" ]]; then
      /bin/echo "Unpacked archive is missing $relative" >&2
      exit 3
    fi
    /usr/bin/shasum -a 256 "$relative"
  done < "$EXPECTED_PATHS"
) > "$UNPACKED_TREE_HASHES"
if ! /usr/bin/cmp -s "$SOURCE_TREE_HASHES" "$UNPACKED_TREE_HASHES"; then
  /bin/echo "Unpacked release bytes differ from the scanned package tree." >&2
  exit 3
fi

/bin/cp "$SOURCE_TREE_HASHES" "$TREE_MANIFEST"
(
  cd "$DIST"
  /usr/bin/shasum -a 256 "${ARCHIVE:t}"
) > "$CHECKSUM"

checksum_line_count="$(/usr/bin/wc -l < "$CHECKSUM" | /usr/bin/tr -d '[:space:]')"
checksum_record="$(<"$CHECKSUM")"
checksum_digest="${checksum_record[1,64]}"
checksum_separator="${checksum_record[65,66]}"
checksum_name="${checksum_record[67,-1]}"
if [[ "$checksum_line_count" != "1" \
  || ! "$checksum_digest" =~ '^[0-9a-f]{64}$' \
  || "$checksum_separator" != "  " \
  || "$checksum_name" != "${ARCHIVE:t}" ]]; then
  /bin/echo "Generated checksum sidecar has invalid grammar or filename." >&2
  exit 3
fi
actual_archive_digest="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
if [[ "$checksum_digest" != "$actual_archive_digest" ]]; then
  /bin/echo "Generated checksum sidecar does not match the release archive." >&2
  exit 3
fi

/bin/mkdir -p "$METADATA_ROOT"
/bin/cp "$CHECKSUM" "$TREE_MANIFEST" "$METADATA_ROOT/"
"$PACKAGE_ROOT/scripts/privacy-scan.sh" "$METADATA_ROOT"
trap - EXIT INT TERM
/bin/rm -rf "$PACKAGE_TEMP"
/bin/echo "$ARCHIVE"
/bin/echo "$CHECKSUM"
/bin/echo "$TREE_MANIFEST"
