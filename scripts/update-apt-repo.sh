#!/usr/bin/env bash
# Regenerates the Sileo/APT repo index (Packages + compressed variants, Release)
# at the repository root, indexing every .deb in dist/. Run from the repo root
# after adding a new deb, then commit the index files and Release.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v dpkg-scanpackages >/dev/null || { echo "dpkg-scanpackages not found (install dpkg-dev)"; exit 1; }
command -v gzip >/dev/null || { echo "gzip not found"; exit 1; }
command -v bzip2 >/dev/null || { echo "bzip2 not found"; exit 1; }
command -v xz >/dev/null || { echo "xz not found"; exit 1; }

dpkg-scanpackages --multiversion dist > Packages
gzip -9 -kf Packages
bzip2 -9 -kf Packages
xz -9 -kf Packages

# Files advertised in Release. Keep uncompressed Packages first so flat-repo
# clients always have a fallback; gz/bz2/xz match what Sileo/apt prefer.
INDEX_FILES=(Packages Packages.gz Packages.bz2 Packages.xz)

filesize() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1"
}

{
  echo "Origin: Lumina Repo"
  echo "Label: Lumina Repo"
  echo "Suite: stable"
  echo "Version: 1.0"
  echo "Codename: lumina"
  # iphoneos-arm64 = Dopamine / rootless; iphoneos-arm64e = RootHide (Relaxin')
  echo "Architectures: iphoneos-arm64 iphoneos-arm64e"
  echo "Components: main"
  echo "Description: Lumina Repo - tweaks by ma6x9x (rootless + roothide)"
  echo "Date: $(date -Ru)"
  echo "MD5Sum:"
  for f in "${INDEX_FILES[@]}"; do
    echo " $(md5sum "$f" | cut -d' ' -f1) $(filesize "$f") $f"
  done
  echo "SHA256:"
  for f in "${INDEX_FILES[@]}"; do
    echo " $(sha256sum "$f" | cut -d' ' -f1) $(filesize "$f") $f"
  done
} > Release

echo "APT repo index updated:"
grep -E '^(Package|Version|Architecture|Filename):' Packages
echo "Index files:"
ls -la "${INDEX_FILES[@]}" Release
