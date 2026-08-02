# Aether — Research & Design Rationale

*Drafted for the overnight build targeting RootHide Bootstrap on iOS 17, with multi-year legs across rootless jails.*

## Landscape (2025–2026)

### RootHide Bootstrap
- Semi-jailbreak / bootstrap for **iOS 15.0–17.0**, A8–A17 / M1–M2, installed via TrollStore.
- **Per-app tweak injection** by design (Bootstrap → App List).
- **2.0 (stable, 2026)** adds SpringBoard / daemon injection on iOS 16–17, auto re-inject after updates, stronger jailbreak-trace hiding, Patcher for converting rootful/rootless debs.
- Native tweaks should build with `THEOS_PACKAGE_SCHEME=roothide` and `iphoneos-arm64e`; use `jbroot()` for jailbreak paths.

### Parallel jails
- **Dopamine** rootless remains the “full” rootless experience on 15/16; 2.5 beta line pushes into 17/18 on arm64.
- NathanLR / Serotonin-class environments still matter for users who want SpringBoard tweaks earlier.

## What people have always asked for

| Request | Status in 2026 | Gap |
|---------|----------------|-----|
| Clipboard history | CopyLog, Kayoko (paid / separate) | No free glass-first HUD baked into a wider tool |
| Activator successor | RemoteCompanion, ZXTouch ports | Script/hardware oriented; not a daily context HUD |
| Hide Reels / Shorts / junk chrome | SCInsta, NoReels, YouMod, ReVanced-style patches | Per-app, break on updates, not a general skill |
| Flex for normals | FLEX 4 (dev explorer) | Too technical; no “tap to banish forever” |
| System-wide dark / CC / theming | Needs SpringBoard; uneven on Bootstrap | Wrong layer for Bootstrap-first users |
| Charge limit / better battery | Partially stock on newer iOS | Less compelling as a RootHide-native bet |

## What still isn’t delivered as one product

A **UIKit-native context layer** that:

1. Works when SpringBoard injection is *off* (classic Bootstrap),
2. Still benefits when SpringBoard injection is *on* (Bootstrap 2.0 / Dopamine),
3. Combines clipboard + screen understanding + durable UI sculpting,
4. Feels like a modern glass OS feature, not a 2014 Cydia panel.

That product is **Aether**.

## Why not “just another clipboard tweak”?

Clipboard alone is solved-ish. The lasting unlock is **Sculpt**: fingerprint a view in the hierarchy and keep it dead across launches. That turns every app into something you can quiet—without waiting for a dedicated Instagram/YouTube tweak author after each App Store update. Lens (Vision OCR) closes the loop: anything you can *see* becomes text you can keep in the timeline.

## Architecture bets (years-long)

- **Filter `com.apple.UIKit`** — Bootstrap App List is the ACL.
- **jbroot-aware prefs/data paths** — one codebase → rootless + RootHide.
- **Modules behind one summon gesture** — ship Clipboard/Lens/Sculpt now; Pulse, Quiet packs, action IPC later without teaching users a new ritual.
- **No SpringBoard requirement for MVP** — survives the “Bootstrap without SB” years and the “SB finally works” years.

## Competitive honesty

- CopyLog is a better *dedicated* clipboard product today.
- SCInsta is a better *Instagram* declutterer today.
- FLEX is a better *runtime explorer* today.

Aether wins by being the **daily-driver layer** that is good enough at all three, RootHide-native, and expandable—so the next five years of requests attach to one gesture instead of five repos.
