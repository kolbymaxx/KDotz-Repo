# CC27

iOS **26-style Control Center** for jailbroken **iOS 15–17** (works alongside rootless + RootHide).

Unlike aesthetic-only tweaks (CC26 / CCXVIII), CC27 focuses on the **real customization UX**:

- **Hold empty space** or tap **+** to enter edit mode (jiggle)
- **Drag** modules to rearrange
- **Corner handle** to cycle sizes (1×1 → 2×1 → 1×2 → 2×2, with smarter options for sliders / connectivity / media)
- **−** to remove a control
- **Add a Control** opens a sheet with a **Search Controls** field
- Gallery lists **system + third-party CCSupport modules + CC27 widgets**
- Liquid-glass module chrome (continuous corners, specular edge)
- Built-in CC27 modules: **Respring**, **Safe Mode**, **UICache**, **Userspace Reboot**

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
