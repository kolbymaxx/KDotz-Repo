#!/usr/bin/env bash
# Publish a built Music27 .deb into the KDotz Repo (kolbymaxx/Siri27).
#
# Usage (from Music27 repo root, after `make package`):
#   ./scripts/publish-to-kdotz.sh
#   ./scripts/publish-to-kdotz.sh /path/to/com.music27.tweak_1.0.2_iphoneos-arm64.deb
#
# Requires: git, dpkg-dev (dpkg-scanpackages), network access to push Siri27.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEB="${1:-}"

if [[ -z "$DEB" ]]; then
  DEB="$(ls -t "$ROOT"/packages/com.music27.tweak_*.deb 2>/dev/null | head -1 || true)"
fi

if [[ -z "${DEB:-}" || ! -f "$DEB" ]]; then
  echo "No Music27 .deb found. Build first: make package FINALPACKAGE=1" >&2
  echo "Or pass a path: $0 /path/to/file.deb" >&2
  exit 1
fi

DEB="$(cd "$(dirname "$DEB")" && pwd)/$(basename "$DEB")"
BASENAME="$(basename "$DEB")"
echo "Publishing $BASENAME → KDotz Repo (kolbymaxx/Siri27)"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

git clone --depth 1 https://github.com/kolbymaxx/Siri27.git "$WORKDIR/Siri27"
cp "$DEB" "$WORKDIR/Siri27/dist/"
(
  cd "$WORKDIR/Siri27"
  bash scripts/update-apt-repo.sh
  git checkout -b "cursor/publish-music27-${BASENAME%.deb}-1f6a" 2>/dev/null \
    || git checkout -b "cursor/publish-music27-$(date +%Y%m%d%H%M%S)-1f6a"
  git add "dist/$BASENAME" Packages Packages.gz Packages.bz2 Packages.xz Release README.md 2>/dev/null || true
  git add "dist/$BASENAME" Packages Packages.gz Packages.bz2 Packages.xz Release
  if git diff --cached --quiet; then
    echo "Nothing to publish (already up to date)."
    exit 0
  fi
  git commit -m "Publish Music27 ${BASENAME#com.music27.tweak_}"
  echo
  echo "Committed on branch $(git branch --show-current)."
  echo "Push with:"
  echo "  cd $WORKDIR/Siri27 && git push -u origin HEAD"
  echo
  echo "Or copy the updated files from: $WORKDIR/Siri27"
  # Keep workdir for the caller if PUBLISH_KEEP=1
  if [[ "${PUBLISH_KEEP:-0}" == "1" ]]; then
    trap - EXIT
    echo "WORKDIR=$WORKDIR"
  fi
)
