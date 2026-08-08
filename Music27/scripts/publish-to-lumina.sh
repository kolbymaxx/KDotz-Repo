#!/usr/bin/env bash
# Publish a built Music27 .deb into Lumina Repo (this monorepo's dist/ + APT index).
#
# Usage (from Music27/, after `make package`):
#   ./scripts/publish-to-lumina.sh
#   ./scripts/publish-to-lumina.sh /path/to/com.music27.tweak_1.0.2_iphoneos-arm64.deb
#
# When run inside the Lumina monorepo, copies into ../dist and regenerates the
# APT index. Outside the monorepo, clones kolbymaxx/lumina-repo instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEB="${1:-}"
REPO_SLUG="kolbymaxx/lumina-repo"

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
echo "Publishing $BASENAME → Lumina Repo ($REPO_SLUG)"

publish_into() {
  local dest="$1"
  mkdir -p "$dest/dist"
  cp "$DEB" "$dest/dist/"
  (
    cd "$dest"
    bash scripts/update-apt-repo.sh
  )
}

# Prefer in-tree monorepo (Music27/ is a sibling of dist/ + scripts/).
if [[ -f "$ROOT/../scripts/update-apt-repo.sh" && -d "$ROOT/../dist" ]]; then
  publish_into "$(cd "$ROOT/.." && pwd)"
  echo
  echo "Updated monorepo APT index. Commit from the repo root:"
  echo "  git add dist/$BASENAME Packages Packages.gz Packages.bz2 Packages.xz Release"
  echo "  git commit -m \"Publish Music27 ${BASENAME#com.music27.tweak_}\""
  exit 0
fi

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

git clone --depth 1 "https://github.com/${REPO_SLUG}.git" "$WORKDIR/lumina-repo"
publish_into "$WORKDIR/lumina-repo"
(
  cd "$WORKDIR/lumina-repo"
  git checkout -b "cursor/publish-music27-${BASENAME%.deb}-1f6a" 2>/dev/null \
    || git checkout -b "cursor/publish-music27-$(date +%Y%m%d%H%M%S)-1f6a"
  git add "dist/$BASENAME" Packages Packages.gz Packages.bz2 Packages.xz Release
  if git diff --cached --quiet; then
    echo "Nothing to publish (already up to date)."
    exit 0
  fi
  git commit -m "Publish Music27 ${BASENAME#com.music27.tweak_}"
  echo
  echo "Committed on branch $(git branch --show-current)."
  echo "Push with:"
  echo "  cd $WORKDIR/lumina-repo && git push -u origin HEAD"
  if [[ "${PUBLISH_KEEP:-0}" == "1" ]]; then
    trap - EXIT
    echo "WORKDIR=$WORKDIR"
  fi
)
