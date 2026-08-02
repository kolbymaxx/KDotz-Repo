# RHCompat

RootHide companion tweak (`com.kolby.rhcompat`) — a **narrow PreferenceLoader / prefs-data shim** for Settings (`Preferences.app` only).

**RootHide (Relaxin’) only.** Ships as `iphoneos-arm64e`.

> **1.0.1 safety note:** 1.0.1 injected into SpringBoard and hooked `open`/`stat` process-wide, which could black-screen after respring. **1.0.2+ does not inject into SpringBoard** and drops those POSIX hooks. If you are stuck on a black screen, see [RECOVERY.md](RECOVERY.md).

## vs official `rootless-compat`

RootHide already ships **[rootless-compat](https://github.com/roothide/DynamicPatches/tree/AutoPatches)** (`AutoPatches.dylib` via PatchLoader). We are **not a replacement** — different layer, complementary job.

| | Official `rootless-compat` | RHCompat (1.0.2+) |
|---|---|---|
| Mechanism | PatchLoader DynamicPatch: **rewrites `/var/jb` string refs inside each tweak binary** before the tweak runs | Substrate tweak in **Preferences.app only**: Foundation path helpers + CFPreferences bridge |
| Best at | Hardcoded `/var/jb/...` literals baked into mach-o | PreferenceLoader / PreferenceBundles / prefs plists + CFPreferences |
| Injects into SpringBoard | No (per-tweak binary patches) | **No** (1.0.1 did — unsafe; removed) |
| Settings UI | No | Yes (enable toggle) |
| Depends on PatchLoader | Yes | No |

**Use both:** keep `rootless-compat` for binary `/var/jb` string patching; use RHCompat for prefs/PreferenceLoader and API-level fallbacks. Coexistence is safe — once a path is already under `jbroot`, RHCompat no-ops.

Where theirs is stronger: compile-time `/var/jb` cstrings/CFStrings never need to pass through a hooked API. Where ours is stronger: classic PreferenceLoader paths without `/var/jb`, non-Apple prefs data under `/var/mobile/Library/Preferences`, and CFPreferences domain bridging.

## What it does

Loads as `000RHCompat.dylib` **only in Preferences**, then rewrites a **limited** path set via Foundation helpers:

| Incoming path | Behavior |
|---|---|
| `/var/jb` / `/private/var/jb` (+ suffix) | → `jbroot(suffix)` |
| `/Library/PreferenceLoader…` | → `jbroot(path)` |
| `/Library/PreferenceBundles…` | → `jbroot(path)` |
| `/var/mobile/Library/Preferences/<non-Apple>.plist` | → jbroot copy when it exists, or when the rootfs file is absent |

Plus light `CFPreferencesCopyAppValue` / `CFPreferencesSetAppValue` bridging for tweak domains. **No** process-wide `open`/`stat`/`posix_spawn` hooks.

## What it deliberately does not do

- No Dobby binary rewriting (that’s `rootless-compat`)
- No broad filesystem virtualization (not libvroot)
- No rewrite of Apple system preference domains
- No SpringBoard / UIKit injection (Preferences.app only)

## Settings

**Settings → RHCompat → Enable path shim** (default on). Respring after toggling.

## Build

Requires [roothide/theos](https://github.com/roothide/theos):

```bash
cd RHCompat
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

## Filter

- Bundles: `com.apple.Preferences`
- Executables: `Preferences`

(No SpringBoard / UIKit.)

## Credits / lineage

- Official layer to complement: [roothide/DynamicPatches `AutoPatches`](https://github.com/roothide/DynamicPatches/tree/AutoPatches) (`rootless-compat`)
- Path resolution follows libroothide `jbroot` + Siri27’s runtime helpers
- Project-Lumina was checked; BootROM research only, no path-compat code reused
