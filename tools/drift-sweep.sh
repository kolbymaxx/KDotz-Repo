#!/usr/bin/env bash
# Phase 0 version-drift sweep: extract SwiftUI from several IPSW dyld caches
# and run swiftmd. Summaries go under $OUT/summaries/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTMD="${ROOT}/tools/swiftmd"
OUT="${1:-/tmp/swiftpeek-dsc}"
mkdir -p "$OUT/summaries"

if [[ ! -x "$SWIFTMD" ]]; then
  cc -O2 -o "$SWIFTMD" "$ROOT/tools/swiftmd.c"
fi

if ! command -v ipsw >/dev/null; then
  echo "ipsw not in PATH" >&2
  exit 1
fi

if [[ -z "${IPSW_APFS_FUSE_PATH:-}" ]]; then
  if command -v apfs-fuse >/dev/null; then
    export IPSW_APFS_FUSE_PATH="$(command -v apfs-fuse)"
  fi
fi

# ver:device:arch
SPECS=(
  "17.3:iPhone13,1:arm64e"
  "17.3.1:iPhone13,1:arm64e"
  "17.2:iPhone13,1:arm64e"
  "17.1:iPhone13,1:arm64e"
  "17.0:iPhone13,1:arm64e"
  "16.7.10:iPhone10,6:arm64"
)

extract_swiftui() {
  local dsc="$1" dest="$2"
  mkdir -p "$dest"
  if [[ -f "$dest/SwiftUI" ]]; then
    return 0
  fi
  ipsw dyld extract "$dsc" \
    "/System/Library/Frameworks/SwiftUI.framework/SwiftUI" \
    --output "$dest" --force --no-color
}

for spec in "${SPECS[@]}"; do
  ver="${spec%%:*}"; rest="${spec#*:}"; dev="${rest%%:*}"; arch="${rest##*:}"
  echo "===== $ver ($dev / $arch) ====="
  verdir="$OUT/$ver"
  mkdir -p "$verdir"

  if ! ls "$verdir"/*/dyld_shared_cache_"$arch" >/dev/null 2>&1; then
    ipsw download ipsw --device "$dev" --version "$ver" \
      --dyld --dyld-arch "$arch" --confirm --output "$verdir"
  fi

  dsc="$(ls -1 "$verdir"/*/dyld_shared_cache_"$arch" | head -1)"
  extdir="$verdir/extracted"
  extract_swiftui "$dsc" "$extdir"

  summary="$OUT/summaries/${ver}.txt"
  hosting="$OUT/summaries/${ver}-hosting.txt"
  "$SWIFTMD" "$extdir/SwiftUI" 2>"$summary" >/dev/null || true
  "$SWIFTMD" "$extdir/SwiftUI" --filter Hosting 2>>"$summary" >"$hosting" || true
  echo "--- summary ---"
  cat "$summary"
done

echo "===== drift comparison (summary lines) ====="
rg -H "descriptors parsed|verdict:|__swift5_types|__swift5_fieldmd" "$OUT/summaries"/*.txt || true
