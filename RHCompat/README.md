# RHCompat

RootHide companion tweak (`com.kolby.rhcompat`) — a **narrow, early-load path shim** focused on PreferenceLoader / prefs-data bridging, with light `/var/jb` API remaps for runtime-built paths.

**RootHide (Relaxin’) only.** Ships as `iphoneos-arm64e`.

## vs official `rootless-compat`

RootHide already ships **[rootless-compat](https://github.com/roothide/DynamicPatches/tree/AutoPatches)** (`AutoPatches.dylib` via PatchLoader). We are **not a replacement** — different layer, complementary job.

| | Official `rootless-compat` | RHCompat |
|---|---|---|
| Mechanism | PatchLoader DynamicPatch: **rewrites `/var/jb` string refs inside each tweak binary** (Dobby ADR/ADRP + `__cfstring`) before the tweak runs | Substrate/ElleKit tweak: **hooks file + CFPreferences APIs** in injected processes |
| Best at | Hardcoded `/var/jb/...` literals baked into mach-o | PreferenceLoader / PreferenceBundles / prefs plists + CFPreferences across schemes |
| Also handles | Per-binary special cases (`fopen`/`access`/`posix_spawn`/Swift `String.append` for hashed packages), pkgmirror | Runtime-concatenated paths that hit `open`/`stat`/…; process-wide for all tweaks in the process |
| Load timing | PatchLoader — **before** TweakLoader | `000RHCompat` + `constructor(101)` among Substrate tweaks |
| Settings UI | No | Yes (enable toggle) |
| Depends on PatchLoader | Yes | No |

**Use both:** keep `rootless-compat` for binary `/var/jb` string patching; use RHCompat for prefs/PreferenceLoader and API-level fallbacks. Coexistence is safe — once a path is already under `jbroot`, RHCompat no-ops.

Where theirs is stronger: compile-time `/var/jb` cstrings/CFStrings never need to pass through a hooked API. Where ours is stronger: classic PreferenceLoader paths without `/var/jb`, non-Apple prefs data under `/var/mobile/Library/Preferences`, and CFPreferences domain bridging.

## What it does

Loads as `000RHCompat.dylib`, then rewrites a **limited** path set:

| Incoming path | Behavior |
|---|---|
| `/var/jb` / `/private/var/jb` (+ suffix) | → `jbroot(suffix)` (API-level; complements AutoPatches) |
| `/Library/PreferenceLoader…` | → `jbroot(path)` |
| `/Library/PreferenceBundles…` | → `jbroot(path)` |
| `/var/mobile/Library/Preferences/<non-Apple>.plist` | → jbroot copy when it exists, or when the rootfs file is absent |

Hooks: `open`/`openat`/`stat`/`lstat`/`access`/`fopen`/`opendir`/`readlink`/`posix_spawn`, common Foundation file helpers, plus light `CFPreferencesCopyAppValue` / `CFPreferencesSetAppValue` bridging for tweak domains.

## What it deliberately does not do

- No Dobby binary rewriting (that’s `rootless-compat`)
- No broad filesystem virtualization (not libvroot)
- No rewrite of Apple system preference domains
- No injection beyond processes that already receive tweaks (`UIKit` / SpringBoard / Preferences; RootHide’s app allowlist still applies)

## Settings

**Settings → RHCompat → Enable path shim** (default on). Respring after toggling.

## Build

Requires [roothide/theos](https://github.com/roothide/theos):

```bash
cd RHCompat
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

## Filter

Injects when any of these match (`Mode = Any`):

- Bundles: `com.apple.springboard`, `com.apple.Preferences`, `com.apple.UIKit`
- Executables: `SpringBoard`, `Preferences`

## Credits / lineage

- Official layer to complement: [roothide/DynamicPatches `AutoPatches`](https://github.com/roothide/DynamicPatches/tree/AutoPatches) (`rootless-compat`)
- Path resolution follows libroothide `jbroot` + Siri27’s runtime helpers
- Project-Lumina was checked; BootROM research only, no path-compat code reused
