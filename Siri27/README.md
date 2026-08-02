# Siri27

iOS 27–style **liquid glass** Siri orb for jailbroken devices.

- Top half: dark glass dome  
- Bottom half: refractive / translucent liquid glass  
- Center: rainbow spectral wave that **grows with speech level**

Package ID: `com.kolby.siri27` (replaces / uninstalls `com.kolby.floatingsiri` on install)

## Install via Sileo — KDotz Repo (easiest — auto-updates)

Add this source in Sileo (Sources → Edit → Add):

```
https://kolbymaxx.github.io/KDotz-Repo/
```

(Backup mirror, same packages: `https://raw.githubusercontent.com/kolbymaxx/KDotz-Repo/main/`)

Then install **Siri27**. Works on both jailbreak types with the same URL:

- Rootless (Dopamine etc.) devices are offered the `iphoneos-arm64` package
- roothide (Relaxin') devices are offered the `iphoneos-arm64e` package

Sileo picks the right one automatically based on your jailbreak's architecture,
and new versions appear as normal updates when the repo is refreshed.

After each new release, regenerate the index with `scripts/update-apt-repo.sh`
and commit `Packages`, `Packages.gz`, and `Release`.

## What’s fixed in 1.30

| Issue | Cause | Fix |
|-------|--------|-----|
| Solid black orb | Backdrop often captured Siri’s dark blur plate; dome read as full pill | Prefer `SBWallpaperController` wallpaper; clear glass background; dome only covers top ~55% with soft mask |
| Rainbow stuck thin | Mic deadzone `0.05` + double `talkingFactor - 0.15` gate ate Siri flame levels | Deadzone `0.002`, higher gain, single 0→1 talking factor, Darwin level bridge |
| iOS 17 / 12 mini | Filter was SpringBoard-only; host VC differs | Inject `SpringBoard` + `SiriViewService` + `Siri`; host on `SBAssistantRootViewController` too |

Glass Metal runtime adapted from [LiquidSiri](https://github.com/Thijs2004/LiquidSiri) / [Liquid (Gl)ass](https://github.com/winaviation-tweaks/liquidass).

## Requirements

- Theos + iOS SDK (macOS build host); roothide builds use the [roothide/theos](https://github.com/roothide/theos) fork
- rootless jailbreak (`iphoneos-arm64`, Dopamine / similar) **or** roothide (`iphoneos-arm64e`, Relaxin')
- Tested target range: **iOS 14–17.3** (iPhone X on 16, iPhone 12 mini on 17.3)

## Build

```bash
cd Siri27
export THEOS=~/theos
make package FINALPACKAGE=1
```

Install the resulting `.deb` with Sileo/Zebra, respring, invoke Siri.

## Settings

**Settings → Siri27**

- Size / position / glow  
- **Top Dome Opacity / Height** — tune the dark-vs-glass split  
- **Mic Gain / Deadzone** — if the rainbow stays thin, raise gain or lower deadzone  
- **Refraction** — strength of the liquid-glass bend  

## Notes

- Stock Siri chrome is dimmed (`alpha ≈ 0.01`) rather than removed so flame audio delegates keep running.  
- If glass still looks black, confirm SpringBoard wallpaper can be snapshotted on your jailbreak and try a brighter wallpaper.  

## Build from your iPhone (no Mac)

1. Open this repo on GitHub in Safari / the GitHub app.
2. Go to **Actions → Build Siri27 → Run workflow**.
3. Wait for the green check.
4. Tap the run → **Artifacts → Siri27-rootless-deb** → download the zip.
5. Unzip in **Filza**, tap the `.deb` → install with **Sileo/Zebra**, respring.
