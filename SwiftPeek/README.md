# SwiftPeek

Read-only SwiftUI / Music view inspector for jailbroken iOS. Recovers live
type names (M1) and optional on-screen strings (M2) without mutating the UI.

**Status:** Phase 1 — M1 + safe M2 `screen_strings` proven on iPhone X /
16.7.14. Live FOVO field meta is **unsafe** on Music — leave Dump Field Meta
**off** (0.3.6). Field **names/layouts** for device-sampled Music types are
recoverable **offline** via `swiftmd` on `MusicApplication.framework`
([docs/OFFLINE_MUSIC_FIELDS.md](docs/OFFLINE_MUSIC_FIELDS.md)). Phase 2–3 host
tools: annotate / query / **ranked targets** / **Theos scaffold** —
[`docs/READ_API.md`](docs/READ_API.md), [`docs/TWEAK_WORKFLOW.md`](docs/TWEAK_WORKFLOW.md),
`PYTHONPATH=tools python3 -m swiftpeek …`. Not published to APT.

## Targets

| Process | Why |
|---------|-----|
| Music | Primary prove device — stay here before any other app |

Music only. Prefs default **off**.

## Prefs

Domain: `com.kolby.swiftpeek`

| Key | Default | Meaning |
|-----|---------|---------|
| `enabled` | `false` | Master kill switch |
| `scanWindows` | `false` | Walk loaded VC tree → coalesced attach dump |
| `dumpFields` | `false` | M2: on-screen UILabel/accessibility strings (**safe**) |
| `dumpFieldMeta` | `false` | Hosting FOVO only; Music 16.7 has no hosts — **leave off** |
| `installHooks` | `false` | Swizzle hosting layout (**leave off**) |
| `logAttach` | `true` | NSLog attach lines when enabled |

**Proven device path:** Enable + Scan Windows + Dump Fields. Field Meta off.
Hooks off. Force-quit Music after pref changes.

## Dumps

```
$jbroot/var/mobile/Library/SwiftPeek/dumps/<process>_<timestamp>.json
$jbroot/var/mobile/Library/SwiftPeek/status.json
```

## Build

```bash
cd SwiftPeek
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless   # iPhone X / Dopamine
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide   # 12 mini / Relaxin
```

ObjC-only dylib (no Swift). Depends on `mobilesubstrate` at runtime.

## Safety

- Read-only. No view mutation.
- Never FOVO-walk Music UIViewControllers or Music UIViews (known crash).
- Install Hooks remains opt-in and off by default.
