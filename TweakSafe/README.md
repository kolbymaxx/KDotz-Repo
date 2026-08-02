# TweakSafe

RootHide companion (`com.kolby.tweaksafe`) — a **Settings-only tweak safety panel**.

Enable/disable installed Substrate/ElleKit tweaks before you respring. No SpringBoard injection, no path hooks.

**Replaces RHCompat** (`com.kolby.rhcompat`). Installing TweakSafe removes RHCompat via dpkg `Replaces`/`Conflicts`, and `postinst` deletes leftover `000RHCompat` dylibs.

## Features

- Lists tweak filter plists under jbroot (`DynamicLibraries` + `TweakInject`)
- Per-tweak on/off (renames `Name.plist` ↔ `Name.plist.disabled`)
- Disable all / Enable all
- Disable recently modified (last 24h) — handy after a bad install
- Respring button
- Shows truncated live `jbroot` path

## What it is not

- Not a `/var/jb` compatibility layer (use official **rootless-compat**)
- Not RHCompat / not a filesystem shim
- Does not inject into SpringBoard

## Build

```bash
cd TweakSafe
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

## Install

RootHide / Relaxin’ Sileo → KDotz Repo → **TweakSafe**. Installing it uninstalls RHCompat.
