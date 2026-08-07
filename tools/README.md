# tools — SwiftPeek host-side recon

## `swiftmd`

Parses a 64-bit Mach-O and dumps Swift type / field names from
`__swift5_types` and `__swift5_fieldmd`.

```bash
cc -O2 -o tools/swiftmd tools/swiftmd.c
python3 tools/mkfixture.py && ./tools/swiftmd /tmp/fixture.macho
# expect: TestKit.MyView with title : Swift.String, tint : SwiftUI.Color
```

**Relative pointer trap:** `RelativeDirectPointer` (names, field records) uses
the full int32 — do **not** mask the low bit. `RelativeIndirectablePointer`
(parent refs) uses bit 0 as an indirect flag.

## Offline Music fields

Live FOVO on Music crashes. Dump field names from the IPSW instead:

```bash
./tools/offline-music-fields.sh /tmp/sp-offline-music
```

See [`SwiftPeek/docs/OFFLINE_MUSIC_FIELDS.md`](../SwiftPeek/docs/OFFLINE_MUSIC_FIELDS.md).

## Host API (`tools/swiftpeek`, v0.6.0)

```bash
cd ~/KDotz-Repo

# Dump workflow
PYTHONPATH=tools python3 -m swiftpeek annotate ~/Downloads/Music_….json -o ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek summary ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek targets ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek scaffold ~/Downloads/annotated.json \
  -o ~/Tweaks/MyMusicTweak --name MyMusicTweak --filter MiniPlayer

# Catalog only (no dump)
PYTHONPATH=tools python3 -m swiftpeek catalog fields MiniPlayer
PYTHONPATH=tools python3 -m swiftpeek catalog find artwork

# Tests (Linux-friendly)
PYTHONPATH=tools python3 -m unittest tools.swiftpeek.test_api tools.swiftpeek.test_scaffold -v
PYTHONPATH=tools python3 -m swiftpeek summary SwiftPeek/docs/fixtures/Music_sample.json
```

Legacy wrappers `annotate-dump.py` / `peek-query.py` still work.
See [`SwiftPeek/docs/READ_API.md`](../SwiftPeek/docs/READ_API.md) and
[`SwiftPeek/docs/TWEAK_WORKFLOW.md`](../SwiftPeek/docs/TWEAK_WORKFLOW.md).
