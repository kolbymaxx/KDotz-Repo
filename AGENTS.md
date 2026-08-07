# AGENTS.md

## Cursor Cloud specific instructions

This repo (`KDotz Repo`) is an **iOS jailbreak tweak monorepo** built with **Theos**
plus a small set of **host-side developer tools**. Understanding the split is the
key thing for working here in a Linux cloud VM.

### What can and cannot run in the cloud VM (Linux)

- The tweaks themselves — `Siri27/`, `Music27/`, `CC27/`, `OmniAI/`, `RHCompat/`,
  `SwiftPeek/` — compile to iOS `.deb` packages via **Theos + Xcode + iOS SDK** and
  **only build on macOS**. Every `build-*.yml` workflow runs on `runs-on: macos-14`.
  Their `Makefile`s `include $(THEOS)/makefiles/common.mk`, and `THEOS` is not (and
  should not be) installed here. Do **not** try to `make package` these on Linux —
  validate tweak changes via the GitHub Actions macOS builders instead.
- The **host-side SwiftPeek recon tools** in `tools/` DO run on this Linux VM and are
  what you develop/verify locally. They only need the base image toolchain
  (`clang`/`cc`, `make`, `python3`, and `dpkg-dev`'s `dpkg-scanpackages`) — all
  already present. No project package manager, no lockfile, nothing to `pip install`.

### Host tool commands (run from repo root)

- Build the Mach-O Swift-metadata parser: `cc -O2 -o tools/swiftmd tools/swiftmd.c`
  (the `tools/swiftmd` binary is intentionally `.gitignore`d; rebuild it as needed).
- Self-test swiftmd end-to-end: `python3 tools/mkfixture.py && ./tools/swiftmd /tmp/fixture.macho`
  → expect `TestKit.MyView` with `title : Swift.String`, `tint : SwiftUI.Color`.
- Join a device dump with offline field layouts, then query it:
  `python3 tools/annotate-dump.py <dump>.json -o annotated.json` then
  `python3 tools/peek-query.py annotated.json summary|types|strings|fields <T>|find <s>`.
  The offline catalog lives at `SwiftPeek/docs/offline/field-catalog.json` (~1955 types).
- See `tools/README.md` and `SwiftPeek/README.md` for the full recon workflow.

### APT / Sileo repo tooling (Linux-runnable)

- `scripts/update-apt-repo.sh` regenerates the `Packages`, `Packages.gz`, and
  `Release` index from the `.deb` files in `dist/` (needs `dpkg-scanpackages`).
  Gotcha: it **rewrites those three tracked files at the repo root**. If you only
  run it to sanity-check, `git checkout -- Packages Packages.gz Release` afterward
  so you don't accidentally commit an index churn. Only commit them when actually
  publishing a new `.deb` (see the "Publishing a new `.deb`" section in `README.md`).

### Notes

- `repo-site/` + `.github/workflows/deploy-repo-pages.yml` publish the static Sileo
  landing page to GitHub Pages; nothing to run locally.
- There is no automated unit-test suite; the `swiftmd` fixture run above is the
  canonical smoke test for host-tool changes.
