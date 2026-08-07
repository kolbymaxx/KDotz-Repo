# tools — SwiftPeek host-side recon

## `swiftmd`

Parses a 64-bit Mach-O and dumps Swift type / field names from
`__swift5_types` and `__swift5_fieldmd`.

```bash
cc -O2 -o tools/swiftmd tools/swiftmd.c
python3 tools/mkfixture.py && ./tools/swiftmd /tmp/fixture.macho
# expect: TestKit.MyView with title : Swift.String, tint : SwiftUI.Color

# Against a cache-extracted SwiftUI:
ipsw dyld extract /path/to/dyld_shared_cache_arm64e \
  /System/Library/Frameworks/SwiftUI.framework/SwiftUI \
  --output /tmp/swiftui-out --force
./tools/swiftmd /tmp/swiftui-out/SwiftUI
./tools/swiftmd /tmp/swiftui-out/SwiftUI --filter Hosting
```

**Relative pointer trap:** `RelativeDirectPointer` (names, field records) uses
the full int32 — do **not** mask the low bit. `RelativeIndirectablePointer`
(parent refs) uses bit 0 as an indirect flag. Conflating them yields empty
strings that look like stripped metadata.

Cache-extracted dylibs often leave mangled *type* strings as `<unresolved>`
when the relative pointer lands outside the file. Field *names* still resolve;
a high unresolved rate means lossy extraction, not missing metadata.

## Drift sweep

```bash
# Requires: ipsw, apfs-fuse (IPSW_APFS_FUSE_PATH), tools/swiftmd
./tools/drift-sweep.sh /tmp/swiftpeek-dsc
```

Downloads remote dyld caches for iPhone13,1 (17.0–17.3.1) and iPhone10,6
(16.7.10), extracts SwiftUI, runs `swiftmd`, writes per-version summaries.

## Offline Music fields

Live FOVO on Music crashes. Dump field names from the IPSW instead:

```bash
./tools/offline-music-fields.sh /tmp/sp-offline-music
# → MusicApplication-summary.txt + MA-NowPlayingContentView.txt …
```

See [`SwiftPeek/docs/OFFLINE_MUSIC_FIELDS.md`](../SwiftPeek/docs/OFFLINE_MUSIC_FIELDS.md).

## Annotate a device dump

```bash
cd ~/KDotz-Repo   # real clone path
git pull origin cursor/swiftpeek-m2-screen-99e4
python3 tools/annotate-dump.py ~/Downloads/Music_YYYY-….json -o ~/Downloads/annotated.json
# → matched N/M nodes; offline_fields from full MusicApplication catalog
```
