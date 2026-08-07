#!/usr/bin/env python3
"""Join a SwiftPeek live dump JSON with offline MusicApplication field layouts.

Usage:
  python3 tools/annotate-dump.py path/to/Music_....json
  python3 tools/annotate-dump.py dump.json -o annotated.json
  python3 tools/annotate-dump.py dump.json --catalog SwiftPeek/docs/offline/field-catalog.json

Does not require a device. Safe companion to 0.3.6 (Field Meta off).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load_catalog(path: Path) -> dict:
    data = json.loads(path.read_text())
    # Also index by trailing component: MusicApplication.Foo -> Foo
    by_short: dict[str, list[str]] = {}
    for full in data:
        short = full.rsplit(".", 1)[-1]
        by_short.setdefault(short, []).append(full)
    return {"full": data, "short": by_short}


def lookup(catalog: dict, type_name: str | None, objc: str | None) -> dict | None:
    full = catalog["full"]
    for cand in (type_name, objc):
        if not cand:
            continue
        if cand in full:
            return {"key": cand, **full[cand]}
        # Strip generic params: Foo<Bar> -> Foo
        base = cand.split("<", 1)[0]
        if base in full:
            return {"key": base, **full[base]}
        short = base.rsplit(".", 1)[-1]
        # Prefer MusicApplication.* when multiple shorts collide
        hits = catalog["short"].get(short) or []
        pref = [h for h in hits if h.startswith("MusicApplication.")]
        chosen = (pref or hits)
        if chosen:
            k = chosen[0]
            return {"key": k, **full[k]}
    return None


def annotate(dump: dict, catalog: dict) -> dict:
    nodes = dump.get("nodes") or []
    annotated = []
    matched = 0
    for node in nodes:
        out = dict(node)
        hit = lookup(catalog, node.get("type"), node.get("objc_class"))
        if hit and hit.get("fields"):
            out["offline_fields"] = hit["fields"]
            out["offline_type"] = hit["key"]
            out["offline_kind"] = hit.get("kind")
            matched += 1
        else:
            out["offline_fields"] = []
        annotated.append(out)

    result = dict(dump)
    result["nodes"] = annotated
    result["offline_annotate"] = {
        "matched_nodes": matched,
        "total_nodes": len(annotated),
        "catalog_types": len(catalog["full"]),
        "note": "layouts from offline swiftmd; not live FOVO",
    }
    return result


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("dump", type=Path, help="SwiftPeek dump JSON from device")
    ap.add_argument(
        "-c",
        "--catalog",
        type=Path,
        default=root / "SwiftPeek/docs/offline/field-catalog.json",
    )
    ap.add_argument("-o", "--output", type=Path, help="Write annotated JSON here")
    ap.add_argument("-q", "--quiet", action="store_true")
    args = ap.parse_args()

    if not args.dump.is_file():
        print(f"missing dump: {args.dump}", file=sys.stderr)
        return 1
    if not args.catalog.is_file():
        print(f"missing catalog: {args.catalog}", file=sys.stderr)
        return 1

    dump = json.loads(args.dump.read_text())
    catalog = load_catalog(args.catalog)
    out = annotate(dump, catalog)

    text = json.dumps(out, indent=2) + "\n"
    if args.output:
        args.output.write_text(text)
    else:
        sys.stdout.write(text)

    if not args.quiet:
        info = out["offline_annotate"]
        print(
            f"# matched {info['matched_nodes']}/{info['total_nodes']} nodes "
            f"against {info['catalog_types']} catalog types",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
