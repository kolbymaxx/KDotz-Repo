# FloatingSiri

iOS 27–style **liquid glass** Siri orb for jailbroken devices.

- Top half: dark glass dome  
- Bottom half: refractive / translucent liquid glass  
- Center: rainbow spectral wave that **grows with speech level**

Package ID: `com.kolby.floatingsiri`

## What’s fixed in 1.30

| Issue | Cause | Fix |
|-------|--------|-----|
| Solid black orb | Backdrop often captured Siri’s dark blur plate; dome read as full pill | Prefer `SBWallpaperController` wallpaper; clear glass background; dome only covers top ~55% with soft mask |
| Rainbow stuck thin | Mic deadzone `0.05` + double `talkingFactor - 0.15` gate ate Siri flame levels | Deadzone `0.002`, higher gain, single 0→1 talking factor, Darwin level bridge |
| iOS 17 / 12 mini | Filter was SpringBoard-only; host VC differs | Inject `SpringBoard` + `SiriViewService` + `Siri`; host on `SBAssistantRootViewController` too |

Glass Metal runtime adapted from [LiquidSiri](https://github.com/Thijs2004/LiquidSiri) / [Liquid (Gl)ass](https://github.com/winaviation-tweaks/liquidass).

## Requirements

- Theos + iOS SDK (macOS build host)
- rootless jailbreak (`iphoneos-arm64`) — Dopamine / similar
- Tested target range: **iOS 14–17.3** (iPhone X on 16, iPhone 12 mini on 17.3)

## Build

```bash
cd FloatingSiri
export THEOS=~/theos
make package FINALPACKAGE=1
```

Install the resulting `.deb` with Sileo/Zebra, respring, invoke Siri.

## Settings

**Settings → Floating Siri**

- Size / position / glow  
- **Top Dome Opacity / Height** — tune the dark-vs-glass split  
- **Mic Gain / Deadzone** — if the rainbow stays thin, raise gain or lower deadzone  
- **Refraction** — strength of the liquid-glass bend  

## Notes

- Stock Siri chrome is dimmed (`alpha ≈ 0.01`) rather than removed so flame audio delegates keep running.  
- If glass still looks black, confirm SpringBoard wallpaper can be snapshotted on your jailbreak and try a brighter wallpaper.  
