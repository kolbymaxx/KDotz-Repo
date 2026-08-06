# SwiftPeek

Read-only SwiftUI view inspector for jailbroken iOS. Recovers Swift type names
(and later field names / layouts) from live `_UIHostingView` hierarchies using
`__swift5_*` reflection metadata.

**Status:** Phase 1 / milestone 2 (Attach + field walk). Not published to the APT repo.

## Targets

| Process | Why |
|---------|-----|
| Music | Primary — SwiftUI-heavy, present on 16.7 and 17.3 |

**Music only.** SpringBoard was removed in 0.2.1 — a Swift-linked tweak in SB
triggered Safe Mode on Dopamine/rootless. Prefs default **off**.

0.2.3 fixes shared-original-IMP swizzling (per-class originals; skip inherited
methods). If an older build still lists SpringBoard in its filter plist, delete
it — Music-only packages cannot affect the lock screen.

First check `…/Library/SwiftPeek/status.json` (heartbeat). A `probe: true` dump
is written when hooks install; attach dumps follow as hosts layout.

## Prefs

Domain: `com.kolby.swiftpeek`

| Key | Default | Meaning |
|-----|---------|---------|
| `enabled` | `false` | Master kill switch (probe-only when on) |
| `scanWindows` | `false` | Walk loaded VC tree for attach dumps |
| `installHooks` | `false` | Swizzle hosting layout (unsafe) |
| `logAttach` | `true` | NSLog attach lines when enabled |
| `dumpFields` | `false` | Field walk (milestone 2; off) |

0.2.7 is **ObjC-only** (no Swift in the dylib). Leave Scan/Hooks off until Music is usable.

PreferenceLoader entry ships with the package. Toggle on, **relaunch Music**
(no respring needed for Music-only), watch `os_log` / Filza dumps for:

```
[SwiftPeek] attach process=Music type=… addr=0x…
```

JSON dumps (milestone 1 writes a minimal one per unique host, capped):

```
$jbroot/var/mobile/Library/SwiftPeek/dumps/<process>_<timestamp>.json
```

Darwin notification on write: `com.kolby.swiftpeek/dump`.

## Build

```bash
cd SwiftPeek
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless   # iPhone X / Dopamine
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide   # 12 mini / Relaxin
```

Depends on `mobilesubstrate` (ElleKit provides it on device). No hard ElleKit
build dependency.

## Phase 0 host tool

See [`../tools/`](../tools/) — `swiftmd` parses Mach-O `__swift5_types` /
`__swift5_fieldmd`. Validated against a synthetic fixture and iOS 17.3 SwiftUI.

## Safety

- Read-only. No view mutation, no AttributeGraph hooks, no POSIX file hooks.
- Fail closed on unexpected metadata.
- Default off. Narrow filter (Music only). Hard process-name gate refuses SpringBoard.

