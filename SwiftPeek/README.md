# SwiftPeek

Read-only SwiftUI / Music view inspector for jailbroken iOS. Recovers live
type names (M1) and optional field layouts / on-screen strings (M2) without
mutating the UI.

**Status:** Phase 1 — M1 proven on device (scan); M2 screen_strings opt-in (0.3.2).
Not published to the APT repo.

## Targets

| Process | Why |
|---------|-----|
| Music | Primary — SwiftUI-heavy, present on 16.7 and 17.3 |

Music only. Prefs default **off**.

## Prefs

Domain: `com.kolby.swiftpeek`

| Key | Default | Meaning |
|-----|---------|---------|
| `enabled` | `false` | Master kill switch |
| `scanWindows` | `false` | Walk loaded VC tree → coalesced attach dump |
| `dumpFields` | `false` | M2: on-screen UILabel/accessibility strings (safe) |
| `dumpFieldMeta` | `false` | M2: Swift field metadata walk (unsafe on Music VCs) |
| `installHooks` | `false` | Swizzle hosting layout (unsafe — leave off) |
| `logAttach` | `true` | NSLog attach lines when enabled |

**Recommended device path:** Enable + Scan Windows for M1. For safe M2 turn on
Dump Fields (titles / UILabel strings). Leave Dump Field Meta and Install Hooks
off — metadata walks crashed Music on 0.3.0.

No respring needed for prefs — force-quit Music.

## Dumps

```
$jbroot/var/mobile/Library/SwiftPeek/dumps/<process>_<timestamp>.json
$jbroot/var/mobile/Library/SwiftPeek/status.json
```

Darwin notification on write: `com.kolby.swiftpeek/dump`.

## Build

```bash
cd SwiftPeek
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless   # iPhone X / Dopamine
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide   # 12 mini / Relaxin
```

ObjC-only dylib (no Swift). Depends on `mobilesubstrate` at runtime.

## Phase 0 host tool

See [`../tools/`](../tools/) — `swiftmd` parses Mach-O `__swift5_types` /
`__swift5_fieldmd`.

## Safety

- Read-only. No view mutation.
- Fail closed on unexpected metadata.
- Never force-load `vc.view`; never swizzle UIKit bases.
- Install Hooks remains opt-in and off by default.

