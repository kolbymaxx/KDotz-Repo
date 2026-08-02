# Aether

**Universal context glass for RootHide Bootstrap and modern rootless jailbreaks.**

Two-finger double-tap in any enabled app → a liquid-glass panel with three tools people have asked for since the Electra era, unified for the first time:

| Module | What it does |
|--------|----------------|
| **Clipboard** | Cross-app clipboard timeline with pin / swipe-delete |
| **Lens** | Vision OCR of the live screen → copy / search-ready text |
| **Sculpt** | Tap any UI chrome to hide it permanently *in that app* |

## Why this exists

RootHide Bootstrap (iOS 15–17) is per-app injection first. Most “system” tweaks assume SpringBoard. Aether is the opposite: **UIKit-wide**, so enabling an app in Bootstrap → App List is enough. On Bootstrap 2.0+ / Dopamine with SpringBoard injection, it works on the home screen too.

Clipboard managers, Activator successors, and per-app declutter tweaks (SCInsta, YouMod, …) all exist in isolation. Aether is a **platform layer** — one gesture, one glass HUD, modules that can grow for years (Quiet packs, Pulse, shareable Sculpt profiles).

## Install

### RootHide Bootstrap
1. Add `https://kolbymaxx.github.io/KDotz-Repo/` in Sileo (Relaxin' / arm64e build).
2. Install **Aether**.
3. Open Bootstrap → **App List** → enable injection for apps you want (Safari, Instagram, YouTube, …).
4. Force-quit and reopen those apps.
5. **Two-finger double-tap** to summon.

### Dopamine / rootless
1. Same repo URL (arm64 build).
2. Install, respring if prompted.
3. Summon gesture works in apps (and SpringBoard when injected).

## Gestures

| Gesture | Action |
|---------|--------|
| Two-finger double-tap | Summon / dismiss Aether |
| Three-finger swipe down | Alternate summon (Settings) |
| In Sculpt: tap a view | Hide it for this app forever |
| In Sculpt: two-finger tap | Exit Sculpt |

## Settings

**Settings → Aether**

- Enable / disable
- Summon gesture
- Clipboard capture + history limit
- Sculpt on/off

## Build

```bash
# rootless (Dopamine)
cd Aether && make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

# RootHide
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
# then set Architecture: iphoneos-arm64e in control for the published deb
```

Requires [Theos](https://theos.dev) (use [roothide/theos](https://github.com/roothide/theos) for RootHide builds).

## Compatibility

- iOS **15.0 – 17.x**
- RootHide Bootstrap 1.x / 2.x
- Dopamine / other rootless
- Filter: `com.apple.UIKit` (every UIKit app you inject into)

## Roadmap (v0.1 is the draft spine)

- [ ] Shareable Sculpt profiles (“Quiet Instagram”, “Reader YouTube”)
- [ ] Pulse — per-app network activity strip
- [ ] Lens → Translate / Search actions
- [ ] Activator-style action hooks for other tweaks
- [ ] Prefs: per-app enable overrides without Bootstrap App List duplication

## Research notes

See [RESEARCH.md](RESEARCH.md) for the jailbreak landscape write-up that led here.

## Credits

Kolby / KDotz Repo · glass language inspired by FloatingSiri’s liquid material work
