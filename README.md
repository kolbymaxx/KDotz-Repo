# KDotz Repo

<p align="center">
  <img src="repo-site/logo.png" width="128" height="128" alt="KDotz Repo logo">
</p>

Sileo / Zebra APT source for Kolby's jailbreak tweaks (rootless + roothide).

## Add in Sileo (Dopamine 3 / rootless)

**Sources → + → Add:**

```
https://raw.githubusercontent.com/kolbymaxx/KDotz-Repo/main/
```

Origin / label: **KDotz Repo**.

> **Why not the github.io URL?** GitHub Pages paths are **case-sensitive**.
> Sileo often lowercases the path (`KDotz-Repo` → `kdotz-repo`), which 404s
> (`Release returned status 404`). The `raw.githubusercontent.com` URL works
> either way. Landing page: https://kolbymaxx.github.io/KDotz-Repo/

### Switched from RootHide (Relaxin') to Dopamine?

RootHide and Dopamine use **different package architectures**. After a clean Dopamine
jailbreak:

1. Remove any leftover KDotz source (especially any `…/kdotz-repo/` entry that 404s)
2. Add `https://raw.githubusercontent.com/kolbymaxx/KDotz-Repo/main/`
3. Pull to refresh — you should see Siri27 / Music27 / CC27 (`iphoneos-arm64`)
4. Do **not** expect RHCompat — that package is RootHide-only (`iphoneos-arm64e`)

Optional later: rename this GitHub repo to all-lowercase `kdotz-repo` so the
Pages URL itself survives Sileo’s lowercasing.

## Packages

| Package | ID | Notes |
|---------|----|--------|
| **Siri27** | `com.kolby.siri27` | iOS 27-style liquid glass Siri orb (rootless + roothide). Replaces FloatingSiri. |
| **Music27** | `com.music27.tweak` | Apple Music Liquid Glass UI for iOS 16/17 (rootless + roothide) |
| **CC27** | `com.kolby.cc27` | iOS 26-style Control Center for iOS 15–17 — edit/resize/add gallery + glass (rootless + roothide). Needs CCSupport. |
| **OmniAI** | `com.kolby.omniai` | System-wide AI (Grok / Claude / Gemini) + screen context + iOS MCP device agent. Replaces GrokAgent. |
| **RHCompat** | `com.kolby.rhcompat` | RootHide PreferenceLoader/prefs companion (**Preferences.app only**, roothide). Use 1.0.2+; 1.0.1 could black-screen. |

One source URL works on both jailbreak types: rootless Sileo installs the
`iphoneos-arm64` builds, roothide (Relaxin') Sileo installs `iphoneos-arm64e`.
RHCompat is published only as `iphoneos-arm64e` (RootHide).

## Publishing a new `.deb`

1. Copy the built package into `dist/`
2. Run `scripts/update-apt-repo.sh`
3. Commit `dist/*.deb`, `Packages`, `Packages.gz`, `Packages.bz2`, `Packages.xz`, and `Release`
4. Push to `main` — GitHub Pages redeploys and Sileo users get the update on refresh

```bash
cp /path/to/com.example_1.2.3_iphoneos-arm64.deb dist/
./scripts/update-apt-repo.sh
git add dist Packages Packages.gz Packages.bz2 Packages.xz Release
git commit -m "Publish com.example 1.2.3"
git push
```

## Layout

- `dist/` — published `.deb` files
- `Packages` / `Packages.gz` / `Packages.bz2` / `Packages.xz` / `Release` — APT index (KDotz Repo)
- `scripts/update-apt-repo.sh` — regenerates the index
- `repo-site/` + `.github/workflows/deploy-repo-pages.yml` — GitHub Pages hosting
- `Siri27/` — Siri27 Theos project
- `Music27/` — Music27 Theos project
- `CC27/` — CC27 Control Center Theos project
- `OmniAI/` — OmniAI system-wide AI Theos project (replaces GrokAgent)
- `RHCompat/` — RootHide compatibility companion (roothide-only)

## Credits

- LiquidSiri by Thijs Mussig
- Liquid (Gl)ass (`liquidass`) by winaviation-tweaks
