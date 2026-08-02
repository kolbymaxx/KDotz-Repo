# RHCompat

RootHide companion tweak (`com.kolby.rhcompat`) — a **narrow, early-load path shim** so older rootless tweaks keep resolving files under RootHide’s randomized `jbroot` without every developer rewriting for `jbroot()`.

**RootHide (Relaxin’) only.** Ships as `iphoneos-arm64e`.

## What it does

Loads as `000RHCompat.dylib` so TweakInject/ElleKit typically initializes it before other tweaks, then rewrites a **limited** path set through hooked file + CFPreferences APIs:

| Incoming path | Behavior |
|---|---|
| `/var/jb` / `/private/var/jb` (+ suffix) | → `jbroot(suffix)` |
| `/Library/PreferenceLoader…` | → `jbroot(path)` |
| `/Library/PreferenceBundles…` | → `jbroot(path)` |
| `/var/mobile/Library/Preferences/<non-Apple>.plist` | → jbroot copy when it exists, or when the rootfs file is absent |

Plus light `CFPreferencesCopyAppValue` / `CFPreferencesSetAppValue` bridging for tweak domains so PreferenceLoader-backed settings resolve into jbroot.

## What it deliberately does not do

- No broad filesystem virtualization (not libvroot)
- No rewrite of Apple system preference domains
- No injection beyond processes that already receive tweaks (`UIKit` / SpringBoard / Preferences filter; RootHide’s app allowlist still applies)
- Not a substitute for RootHidePatcher / DynamicPatches on heavily incompatible packages

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

Path resolution follows the same RootHide `jbroot` model used in Siri27’s runtime helpers and [libroothide](https://github.com/roothide/libroothide). Project-Lumina was checked for reusable shim logic; it is BootROM research only and contributed no path-compat code here.
