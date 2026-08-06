# SwiftPeek

Read-only SwiftUI / Music view inspector for jailbroken iOS. Recovers live
type names (M1) and optional field layouts / on-screen strings (M2) without
mutating the UI.

**Status:** Phase 1 — M1 proven on device (scan); M2 field walk opt-in (0.3.0).
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
| `dumpFields` | `false` | M2: field names/offsets + screen_strings (no Mirror) |
| `installHooks` | `false` | Swizzle hosting layout (unsafe — leave off) |
| `logAttach` | `true` | NSLog attach lines when enabled |

**Recommended device path:** Enable + Scan Windows. After M1 dumps look good,
turn on Dump Fields, force-quit Music, wait ~12s. Expect `milestone: 2` and
`fields` / `screen_strings` in the coalesced scan dump.

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

