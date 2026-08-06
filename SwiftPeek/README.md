# SwiftPeek

Read-only SwiftUI / Music view inspector for jailbroken iOS. Recovers live
type names (M1) and optional field layouts / on-screen strings (M2) without
mutating the UI.

**Status:** Phase 1 — M1 + `screen_strings` proven; Music 16.7 has **no**
`_UIHostingView` in-window (0.3.4 sample). 0.3.5 adds allowlisted Music
**UIView** field meta (never UIViewControllers). Not published to APT.

## Targets

| Process | Why |
|---------|-----|
| Music | Primary — SwiftUI-heavy on some OS versions; UIKit/Swift views on 16.7 |

Music only. Prefs default **off**.

## Prefs

Domain: `com.kolby.swiftpeek`

| Key | Default | Meaning |
|-----|---------|---------|
| `enabled` | `false` | Master kill switch |
| `scanWindows` | `false` | Walk loaded VC tree → coalesced attach dump |
| `dumpFields` | `false` | M2: on-screen UILabel/accessibility strings (safe) |
| `dumpFieldMeta` | `false` | M2: field metadata on hosting or allowlisted Music UIViews |
| `installHooks` | `false` | Swizzle hosting layout (unsafe — leave off) |
| `logAttach` | `true` | NSLog attach lines when enabled |

**Music UIView allowlist (meta):** `NowPlayingContentView`,
`PaletteContainerView`, `UberNavigationTitleView`,
`MusicArtworkComponentImageView`, `NowPlayingTransportControlStackView`,
`NowPlayingVibrancyEffectView`. Depth 0 only. Controllers still refused.

No respring needed for prefs — force-quit Music.

## Dumps

```
$jbroot/var/mobile/Library/SwiftPeek/dumps/<process>_<timestamp>.json
$jbroot/var/mobile/Library/SwiftPeek/status.json
```

Look for `tool_version: "0.3.5"` and
`hosts=N music_views=N tried=N hit=N`. Nodes may be `scan_music_view`
with a `fields` array.

## Build

```bash
cd SwiftPeek
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless   # iPhone X / Dopamine
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide   # 12 mini / Relaxin
```

ObjC-only dylib (no Swift). Depends on `mobilesubstrate` at runtime.

## Safety

- Read-only. No view mutation.
- Never FOVO-walk Music UIViewControllers (0.3.0 crash).
- Field meta: depth 0; no value previews; no nested walks.
- Install Hooks remains opt-in and off by default.
