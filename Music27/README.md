# Music27

Jailbreak tweak that restyles **Apple Music on iOS 16 / 17** toward the **iOS 26 / 27 Liquid Glass** look:

- Floating glass tab bar (continuous corners, soft specular edge, ultra-thin material)
- Rounded floating mini-player chrome
- Artwork-driven color wash on album / playlist / now-playing (translucent, behind content)
- **Pinned** row at the top of Library + Pin / Unpin in context menus and detail nav bars

Settings live under **Settings → Music27**.

## Black-screen fix (1.0.0 → 1.0.1)

The shipped `1.0.0-3+debug` deb painted the whole Music app black. Root causes:

1. **`M27LooksLikeAlbumOrPlaylist` matched any class containing `container`**, which includes Music’s root container view controller — so the color wash ran on the entire app.
2. **`M27ApplyWash` inserted an opaque `UIView` as a subview.** On iOS 16/17 Music is largely SwiftUI; hosting layers render under UIKit subviews, so the opaque “background” covered all content.
3. **No-artwork fallback used `systemGrayColor` darkened ~75%**, which is near-black — so even screens without artwork got a black overlay.
4. **Glass chrome was re-applied on every `layoutSubviews`**, which invalidated layout and caused an endless relayout loop.

1.0.1 fixes all four: stricter matchers, translucent `CAGradientLayer` wash behind content, no theme without artwork, and one-shot chrome stripping.

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

This approximates Liquid Glass with `UIVisualEffectView` + continuous corners + specular border. It is **not** Apple’s private Liquid Glass renderer. Full SwiftUI restyling of every Music surface is out of scope for a UIKit-hook tweak; glass chrome, pins, and themed washes are what this delivers reliably.
