# SwiftPeek

Read-only SwiftUI / Music view inspector for jailbroken iOS. Recovers live
type names (M1) and optional field layouts / on-screen strings (M2) without
mutating the UI.

**Status:** Phase 1 — M1 + safe M2 `screen_strings` proven on device (0.3.2);
hardened hosting-view field meta opt-in (0.3.3). Not published to the APT repo.

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
| `dumpFieldMeta` | `false` | M2: Swift field metadata on hosting views only |
| `installHooks` | `false` | Swizzle hosting layout (unsafe — leave off) |
| `logAttach` | `true` | NSLog attach lines when enabled |

**Recommended device path:** Enable + Scan Windows + Dump Fields (proven).
For hardened meta, also turn on Dump Field Meta — it only walks
`_UIHostingView` / `UIHostingView` (depth 0: names/offsets/types). Leave
Install Hooks off. Music VC metadata walks crashed on 0.3.0 and are refused.

No respring needed for prefs — force-quit Music.

## Dumps

```
$jbroot/var/mobile/Library/SwiftPeek/dumps/<process>_<timestamp>.json
$jbroot/var/mobile/Library/SwiftPeek/status.json
```

Darwin notification on write: `com.kolby.swiftpeek/dump`.

Look for `tool_version: "0.3.3"`. With meta on, scan message includes
`meta=1 tried=N hit=N` and hosting `scan_view` nodes may carry `fields`.

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
- Field meta: hosting UIViews only; no value previews; no nested walks.
- Install Hooks remains opt-in and off by default.
