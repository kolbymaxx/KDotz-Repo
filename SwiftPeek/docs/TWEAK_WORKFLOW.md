# SwiftPeek → Music tweak workflow

Turn a **0.3.6** Music dump into a starter Theos project without live FOVO.

## Device (once)

1. SwiftPeek prefs: Enable + Scan Windows + Dump Fields **on**; Field Meta **off**; Hooks **off**.
2. Open Music, visit Library / Search / Now Playing / MiniPlayer.
3. Pull the dump JSON off the phone (Filza → Mac `~/Downloads/`).

## Host (Mac / this repo)

```bash
cd ~/lumina-repo
git pull origin main

# Annotate (optional — targets/scaffold auto-annotate)
PYTHONPATH=tools python3 -m swiftpeek annotate ~/Downloads/Music_….json \
  -o ~/Downloads/annotated.json

# Rank what is worth hooking
PYTHONPATH=tools python3 -m swiftpeek targets ~/Downloads/annotated.json

# Emit a Music-only Theos skeleton
PYTHONPATH=tools python3 -m swiftpeek scaffold ~/Downloads/annotated.json \
  -o ~/Tweaks/MyMusicTweak \
  --name MyMusicTweak \
  --filter MiniPlayer
```

## What you get

| File | Purpose |
|------|---------|
| `TARGETS.md` | Ranked types + screen strings + interesting offline fields |
| `src/Tweak.x` | One `%hook UIViewController` + `class_getName` filters (Music27 pattern) |
| `Makefile` / `control` / `*.plist` | Rootless Theos, Music filter only |

## Build & install

```bash
cd ~/Tweaks/MyMusicTweak
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
# install deb on Dopamine / iPhone X, force-quit Music
```

## Developing the tweak

1. Pick a high-score type from `TARGETS.md`.
2. Fill the TODO in `Tweak.x` — prefer `valueForKey:` with offline field names from:

   ```bash
   PYTHONPATH=tools python3 -m swiftpeek fields ~/Downloads/annotated.json MiniPlayer
   PYTHONPATH=tools python3 -m swiftpeek find ~/Downloads/annotated.json artwork
   ```

3. Do **not** enable SwiftPeek Dump Field Meta on device.
4. Keep the filter Music-only (`com.apple.Music`).

## Safety (do not regress)

- Never FOVO-walk Music UIViewControllers or Music UIViews on device.
- Never force `vc.view`; do not swizzle UIKit bases for SwiftPeek’s hooks path.
- Scaffold hooks UIKit bases and **filters by class name** — same idea as Music27.
