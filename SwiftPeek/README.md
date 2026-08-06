# SwiftPeek

Read-only SwiftUI / Music view inspector for jailbroken iOS. Recovers live
type names (M1) and optional field layouts / on-screen strings (M2) without
mutating the UI.

**Status:** Phase 1 — M1 + safe M2 `screen_strings` proven (0.3.2); hardened
field meta stable with meta on (0.3.3, `tried=0`); broader hosting-view
discovery (0.3.4). Not published to the APT repo.

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

**Recommended device path:** Enable + Scan Windows + Dump Fields. For meta,
also Dump Field Meta — walks `_UIHostingView` only (depth 0). Leave Install
Hooks off.

No respring needed for prefs — force-quit Music.

## Dumps

```
$jbroot/var/mobile/Library/SwiftPeek/dumps/<process>_<timestamp>.json
$jbroot/var/mobile/Library/SwiftPeek/status.json
```

Darwin notification on write: `com.kolby.swiftpeek/dump`.

Look for `tool_version: "0.3.4"`. Scan message includes
`hosts=N tried=N hit=N`. If meta is on and `hosts=0`, dumps may include
`view_class_sample` to show what was visible under the window.

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
