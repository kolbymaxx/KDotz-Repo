# SwiftPeek Phase 2–3 — host read API + tweak scaffold

Stable **read** surface over Phase 1 artifacts:

- live dump JSON (device, Field Meta off)
- offline `field-catalog.json` (swiftmd)

Phase 3 adds **ranked targets** and a **Theos scaffold** generator (Music-only).
See [`TWEAK_WORKFLOW.md`](TWEAK_WORKFLOW.md).

No live FOVO. Safe with **0.3.6**.

## Install / path

From the repo root (or `tools/` on `PYTHONPATH`):

```bash
cd ~/KDotz-Repo
git pull origin main   # or the feature branch
```

## Python API

```python
from tools.swiftpeek import FieldCatalog, PeekSession, annotate_dump
# or, with cwd/tools on path:
from swiftpeek import PeekSession

sess = PeekSession("~/Downloads/Music_….json")  # auto-annotates
print(sess.summary())
print(sess.fields("MiniPlayer"))
for hit in sess.find("artwork"):
    print(hit.type_name, hit.name, hit.type_hint)
```

## CLI

```bash
# Preferred
PYTHONPATH=tools python3 -m swiftpeek annotate ~/Downloads/Music_….json -o ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek summary ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek types ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek fields ~/Downloads/annotated.json MiniPlayer
PYTHONPATH=tools python3 -m swiftpeek find ~/Downloads/annotated.json artwork
PYTHONPATH=tools python3 -m swiftpeek targets ~/Downloads/annotated.json
PYTHONPATH=tools python3 -m swiftpeek scaffold ~/Downloads/annotated.json \
  -o ~/Tweaks/MyMusicTweak --name MyMusicTweak --filter MiniPlayer

# Legacy wrappers (still work)
python3 tools/annotate-dump.py ~/Downloads/Music_….json -o ~/Downloads/annotated.json
python3 tools/peek-query.py ~/Downloads/annotated.json summary
```

## Tests

```bash
PYTHONPATH=tools python3 -m unittest tools.swiftpeek.test_api tools.swiftpeek.test_scaffold -v
# or
cd tools && python3 -m unittest swiftpeek.test_api swiftpeek.test_scaffold -v
```

## Version

API version `0.5.0` is stamped into `offline_annotate.api_version` on annotate.
