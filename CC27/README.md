# CC27

iOS **26-style Control Center** for jailbroken **iOS 15–17** (works alongside rootless + RootHide).

Unlike aesthetic-only tweaks (CC26 / CCXVIII), CC27 focuses on the **real customization UX**:

- **Hold empty space** or tap **+** to enter edit mode (jiggle)
- **Drag** modules to rearrange
- **−** to remove a control
- **Add a Control** opens a searchable list gallery (Available / All)
- Gallery lists **system + third-party CCSupport modules + CC27 widgets**
- Liquid-glass module chrome (round 1×1 / pill modules; expanded menus stay unclipped)
- Built-in CC27 modules: **Respring**, **Safe Mode**, **UICache**, **Userspace Reboot**

## 1.0.2 fixes

- Restored round / pill module glass (clips collapsed modules; still skips expanded menus)
- Removed resize entirely — the old size override path could safe-mode SpringBoard
- Gallery icons: unique SF Symbols per control (no more blank white squares / identical glyphs)
- Settings → CC27 → Respring works on rootless / RootHide

## 1.0.1 fixes

- Top **+** / power buttons stay visible while Control Center is open
- Add Control gallery uses readable list rows (no overlapping “System” labels)
- Adding a control reloads module instances (or prompts one reopen if needed)
- Expanded menus no longer cut into a circle by glass clipping

## Install

Add **KDotz Repo** in Sileo:

```
https://kolbymaxx.github.io/KDotz-Repo/
```

Install **CC27** (depends on **CCSupport**). Respring. Open Control Center → tap **+** or touch & hold empty space.

Settings live under **Settings → CC27**.

## Build

```bash
cd CC27
export THEOS=~/theos
make package FINALPACKAGE=1
# RootHide:
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

Or run **Actions → Build CC27** on GitHub and grab the artifact `.deb`.

## Notes

- Requires [CCSupport](https://github.com/opa334/CCSupport) so `/Library/ControlCenter/Bundles` modules and the CC27 provider load.
- Conflicts with CC26 / CCXVIII / CC18 (overlapping Control Center chrome).
- Resize is an approximation of iOS 26’s freeform grid on top of the iOS 15–17 modular layout engine.
- Target: **iOS 15–17**; may load on 14 but is not the focus.
