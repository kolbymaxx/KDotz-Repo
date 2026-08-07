# SwiftPeek Phase 2–3 — host read API + tweak scaffold

Stable **read** surface over Phase 1 artifacts:

- live dump JSON (device, Field Meta off)
- offline `field-catalog.json` (swiftmd)

Phase 3 adds **ranked targets** and a **Theos scaffold** generator (Music-only).
Phase 3.1 adds **catalog browse** (no dump) and richer KVC stubs in scaffolds.
See [`TWEAK_WORKFLOW.md`](TWEAK_WORKFLOW.md).

No live FOVO. Safe with **0.3.6**.

## Install / path

```bash
cd ~/KDotz-Repo
git pull origin main
```

## Python API

```python
from swiftpeek import PeekSession, FieldCatalog

sess = PeekSession("~/Downloads/Music_….json")  # auto-annotates
print(sess.summary())
print(sess.fields("MiniPlayer"))
for hit in sess.find("artwork"):
    print(hit.type_name, hit.name, hit.type_hint)

cat = FieldCatalog()
print(cat.search_types("MiniPlayer"))
print(cat.find_fields("artwork")[:10])
```

## CLI

```bash
# Dump → annotate / query
PYTHONPATH=tools python3 -m swiftpeek annotate ~/Downloads/Music_….json -o ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek summary ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek fields ~/Downloads/annotated.json MiniPlayer
PYTHONPATH=tools python3 -m swiftpeek find ~/Downloads/annotated.json artwork
PYTHONPATH=tools python3 -m swiftpeek targets ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek scaffold ~/Downloads/annotated.json \
  -o ~/Tweaks/MyMusicTweak --name MyMusicTweak --filter MiniPlayer

# Catalog only (no dump / no Filza pull needed)
PYTHONPATH=tools python3 -m swiftpeek catalog types MiniPlayer
PYTHONPATH=tools python3 -m swiftpeek catalog fields MiniPlayer
PYTHONPATH=tools python3 -m swiftpeek catalog find artwork

# Fixture smoke (checked in)
PYTHONPATH=tools python3 -m swiftpeek summary SwiftPeek/docs/fixtures/Music_sample.json
```

## Tests

```bash
PYTHONPATH=tools python3 -m unittest tools.swiftpeek.test_api tools.swiftpeek.test_scaffold -v
```

## Version

API version `0.6.0` is stamped into `offline_annotate.api_version` on annotate.
