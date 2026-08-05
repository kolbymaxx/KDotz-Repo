# KDotz Repo

<p align="center">
  <img src="repo-site/logo.png" width="128" height="128" alt="KDotz Repo logo">
</p>

Sileo / Zebra APT source for Kolby's jailbreak tweaks (rootless + roothide).

## Add in Sileo

**Sources → Edit → Add:**

```
https://kolbymaxx.github.io/KDotz-Repo/
```

Backup mirror (same packages): `https://raw.githubusercontent.com/kolbymaxx/KDotz-Repo/main/`

Origin / label: **KDotz Repo**

## Packages

| Package | ID | Notes |
|---------|----|--------|
| **Siri27** | `com.kolby.siri27` | iOS 27-style liquid glass Siri orb (rootless + roothide). Replaces FloatingSiri. |
| **Music27** | `com.music27.tweak` | Apple Music Liquid Glass UI for iOS 16/17 (rootless + roothide) |
| **CC27** | `com.kolby.cc27` | iOS 26-style Control Center for iOS 15–17 — edit/resize/add gallery + glass (rootless + roothide). Needs CCSupport. |
| **RHCompat** | `com.kolby.rhcompat` | RootHide PreferenceLoader/prefs companion (**Preferences.app only**, roothide). Use 1.0.2+; 1.0.1 could black-screen. |

One source URL works on both jailbreak types: rootless Sileo installs the
`iphoneos-arm64` builds, roothide (Relaxin') Sileo installs `iphoneos-arm64e`.
RHCompat is published only as `iphoneos-arm64e` (RootHide).

## Publishing a new `.deb`

1. Copy the built package into `dist/`
2. Run `scripts/update-apt-repo.sh`
3. Commit `dist/*.deb`, `Packages`, `Packages.gz`, and `Release`
4. Push to `main` — GitHub Pages redeploys and Sileo users get the update on refresh

```bash
cp /path/to/com.example_1.2.3_iphoneos-arm64.deb dist/
./scripts/update-apt-repo.sh
git add dist Packages Packages.gz Release
git commit -m "Publish com.example 1.2.3"
git push
```

## Layout

- `dist/` — published `.deb` files
- `Packages` / `Packages.gz` / `Release` — APT index (KDotz Repo)
- `scripts/update-apt-repo.sh` — regenerates the index
- `repo-site/` + `.github/workflows/deploy-repo-pages.yml` — GitHub Pages hosting
- `Siri27/` — Siri27 Theos project
- `Music27/` — Music27 Theos project
- `CC27/` — CC27 Control Center Theos project
- `RHCompat/` — RootHide compatibility companion (roothide-only)

## Credits

- LiquidSiri by Thijs Mussig
- Liquid (Gl)ass (`liquidass`) by winaviation-tweaks
