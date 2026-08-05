# Music27

Jailbreak tweak that restyles **Apple Music on iOS 16 / 17** toward the **iOS 26 / 27 Liquid Glass** look:

- **Floating glass dock**
  - **Expanded:** mini-player glass pill stacked above a 5-tab glass pill
  - **Collapsed (after scroll down):** merged pill with red Music button · now playing · Search
  - Tap the **red button** to expand back to the 5-tab layout
- **Album / playlist controls:** Shuffle (circle) · Play (pill) · Download (circle)
- Artwork-driven color wash on album / playlist / now-playing
- **Pinned** row at the top of Library + Pin / Unpin in context menus and detail nav bars

Settings live under **Settings → Music27**.

## Dock behavior

1. Fresh launch starts **expanded** (tabs visible).
2. Scrolling down collapses into the merged red · mini · Search pill.
3. Collapsed state stays until you tap the red Music button, which expands again.

## 1.1.1 blank-screen fix

1.1.0 could white-screen Music on launch by (a) mutating safe-area insets every
layout pass and (b) walking/hiding views in the tab controller content tree
while looking for the mini player. 1.1.1 installs the dock once, only fades
strict mini-player matches that are siblings of the tab bar, and never hides
content hosts.

## Install via Sileo (KDotz Repo — recommended)

Add this source in Sileo (**Sources → Edit → Add**):

```
https://raw.githubusercontent.com/kolbymaxx/Siri27/main/
```

Then search for **Music27** and install. New versions show up as normal Sileo updates when the repo is refreshed.

Manual / Filza: install `packages/com.music27.tweak_*.deb`, respring, force-quit and relaunch **Music**. Toggle features under **Settings → Music27**.

Architecture: `iphoneos-arm64` (rootless, files under `/var/jb`).

## Build

```bash
export THEOS=/opt/theos
make package FINALPACKAGE=1
```

Requires Theos with an iOS 15+ SDK (this project targets `iphone:clang:16.5:15.0`) and a rootless packaging scheme.

## Publish updates to KDotz Repo

After building a new `.deb`, publish it into [KDotz Repo](https://github.com/kolbymaxx/Siri27) (`dist/` + apt index):

```bash
./scripts/publish-to-kdotz.sh
# then push the branch it creates on kolbymaxx/Siri27 (or merge to main)
```

Or copy the deb into `Siri27/dist/` and run `scripts/update-apt-repo.sh` there, then commit `Packages`, `Packages.gz`, and `Release`.

## Scope / honesty

This approximates Liquid Glass with `UIVisualEffectView` + continuous corners + specular border + soft shadow. It is **not** Apple’s private Liquid Glass renderer. The dock replaces Music’s stock tab bar / mini-player chrome visually while forwarding tab selection, Search, play/pause (MediaRemote), and Now Playing presentation to Music’s real controllers.
