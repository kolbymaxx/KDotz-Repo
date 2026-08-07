#!/usr/bin/env bash
# Offline field dump for MusicApplication (16.7.x IPSW) + optional DSC companions.
# Does not touch a device. Writes text under $OUT (default /tmp/sp-offline-music).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTMD="${ROOT}/tools/swiftmd"
OUT="${1:-/tmp/sp-offline-music}"
VER="${MUSIC_IPSW_VERSION:-16.7.10}"
DEV="${MUSIC_IPSW_DEVICE:-iPhone10,6}"
mkdir -p "$OUT"

if [[ ! -x "$SWIFTMD" ]]; then
  cc -O2 -o "$SWIFTMD" "$ROOT/tools/swiftmd.c"
fi

if ! command -v ipsw >/dev/null; then
  echo "ipsw not in PATH" >&2
  exit 1
fi

MA_CANDIDATE="$(find /tmp/sp-music-bundle /tmp/sp-music-ma -name MusicApplication -type f 2>/dev/null | head -1 || true)"
if [[ -z "${MA_CANDIDATE}" ]]; then
  echo "===== extracting MusicApplication from $DEV $VER ====="
  URL="$(ipsw download ipsw --device "$DEV" --version "$VER" --urls --confirm --no-color \
        | rg -o 'https://[^ ]+\.ipsw' | head -1)"
  test -n "$URL"
  ipsw extract --remote "$URL" --files \
    --pattern 'MusicApplication\.framework/MusicApplication$' \
    -o /tmp/sp-music-ma --no-color
  MA_CANDIDATE="$(find /tmp/sp-music-ma -name MusicApplication -type f | head -1)"
fi

echo "MusicApplication=$MA_CANDIDATE"
"$SWIFTMD" "$MA_CANDIDATE" 2>"$OUT/MusicApplication-summary.txt" >/dev/null || true
cat "$OUT/MusicApplication-summary.txt"

FILTERS=(
  NowPlayingContentView PaletteContainerView UberNavigationTitleView
  NowPlayingTransport NowPlayingVibrancy MiniPlayerView SyncedLyrics
  TabBarController LibraryViewController HostingView
)
for f in "${FILTERS[@]}"; do
  "$SWIFTMD" "$MA_CANDIDATE" --filter "$f" >"$OUT/MA-${f}.txt" 2>/dev/null || true
  echo "wrote $OUT/MA-${f}.txt ($(wc -l < "$OUT/MA-${f}.txt") lines)"
done

echo "done → $OUT"
