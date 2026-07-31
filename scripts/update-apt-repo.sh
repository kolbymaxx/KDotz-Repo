#!/usr/bin/env bash
# Regenerates the Sileo/APT repo index (Packages, Packages.gz, Release) at the
# repository root, indexing every .deb in dist/. Run from the repo root after
# adding a new deb, then commit Packages, Packages.gz and Release.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v dpkg-scanpackages >/dev/null || { echo "dpkg-scanpackages not found (install dpkg-dev)"; exit 1; }

dpkg-scanpackages --multiversion dist > Packages
gzip -9 -kf Packages

{
  echo "Origin: KDotz Repo"
  echo "Label: KDotz Repo"
  echo "Suite: stable"
  echo "Version: 1.0"
  echo "Codename: kdotz"
  echo "Architectures: iphoneos-arm64 iphoneos-arm64e"
  echo "Components: main"
  echo "Description: KDotz Repo — tweaks by Kolby (rootless + roothide)"
  echo "Date: $(date -Ru)"
  echo "MD5Sum:"
  for f in Packages Packages.gz; do
    echo " $(md5sum "$f" | cut -d' ' -f1) $(stat -c%s "$f" 2>/dev/null || stat -f%z "$f") $f"
  done
  echo "SHA256:"
  for f in Packages Packages.gz; do
    echo " $(sha256sum "$f" | cut -d' ' -f1) $(stat -c%s "$f" 2>/dev/null || stat -f%z "$f") $f"
  done
} > Release

echo "APT repo index updated:"
grep -E '^(Package|Version|Architecture|Filename):' Packages
