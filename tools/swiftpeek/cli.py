#!/usr/bin/env python3
"""Unified SwiftPeek host CLI.

  python3 -m swiftpeek annotate DUMP.json -o annotated.json
  python3 -m swiftpeek summary annotated.json
  python3 -m swiftpeek types annotated.json
  python3 -m swiftpeek strings annotated.json
  python3 -m swiftpeek fields annotated.json MiniPlayer
  python3 -m swiftpeek find annotated.json artwork
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow `python3 -m swiftpeek` from tools/ or repo root.
if __name__ == "__main__" and (__package__ is None or __package__ == ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    __package__ = "swiftpeek"

from .api import FieldCatalog, PeekSession, annotate_dump, load_dump
from .paths import DEFAULT_CATALOG


def _cmd_annotate(args: argparse.Namespace) -> int:
    if not args.dump.is_file():
        print(f"missing dump: {args.dump}", file=sys.stderr)
        return 1
    cat = FieldCatalog(args.catalog)
    out = annotate_dump(load_dump(args.dump), cat)
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


def _session(args: argparse.Namespace) -> PeekSession:
    return PeekSession(args.dump, FieldCatalog(args.catalog), annotate=True)


def _cmd_summary(args: argparse.Namespace) -> int:
    s = _session(args).summary()
    for k in (
        "tool_version",
        "milestone",
        "message",
        "nodes",
        "matched_nodes",
        "catalog_types",
        "with_fields",
        "with_strings",
    ):
        label = {
            "tool_version": "tool_version",
            "milestone": "milestone",
            "message": "message",
            "nodes": "nodes",
            "matched_nodes": "offline",
            "catalog_types": "catalog",
            "with_fields": "with_fields",
            "with_strings": "with_strings",
        }[k]
        if k == "matched_nodes":
            print(f"offline:      {s.get('matched_nodes')}/{s.get('nodes')} matched "
                  f"({s.get('catalog_types')} catalog types)")
        elif k == "catalog_types":
            continue
        else:
            print(f"{label + ':':13} {s.get(k)}")
    return 0


def _cmd_types(args: argparse.Namespace) -> int:
    for row in _session(args).iter_types():
        print(
            f"{row['field_count']:3d}f {row['string_count']:2d}s  "
            f"{(row.get('role') or ''):16} {row.get('type')}"
        )
    return 0


def _cmd_strings(args: argparse.Namespace) -> int:
    for n in _session(args).nodes:
        ss = n.get("screen_strings") or []
        if not ss:
            continue
        print(f"## {n.get('type') or '?'}")
        for s in ss:
            print(f"  - {s}")
        print()
    return 0


def _cmd_fields(args: argparse.Namespace) -> int:
    rows = _session(args).fields(args.needle)
    if not rows:
        print(f"no nodes matching {args.needle!r}", file=sys.stderr)
        return 1
    for row in rows:
        print(f"## {row['type']}")
        for f in row["fields"]:
            print(f"  [{f.get('index')}] {f.get('name')} : {f.get('type')}")
        print()
    return 0


def _cmd_find(args: argparse.Namespace) -> int:
    hits = _session(args).find(args.needle)
    for h in hits:
        if h.source == "screen_string":
            print(f"{h.type_name} screen_string={h.name!r}")
        else:
            print(f"{h.type_name}.{h.name} : {h.type_hint}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="swiftpeek", description=__doc__)
    ap.add_argument(
        "--catalog",
        type=Path,
        default=DEFAULT_CATALOG,
        help=f"field catalog JSON (default: {DEFAULT_CATALOG})",
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("annotate", help="join dump with offline fields")
    p.add_argument("dump", type=Path)
    p.add_argument("-o", "--output", type=Path)
    p.add_argument("-q", "--quiet", action="store_true")
    p.set_defaults(func=_cmd_annotate)

    for name, help_, fn in (
        ("summary", "dump overview", _cmd_summary),
        ("types", "list node types", _cmd_types),
        ("strings", "list screen_strings", _cmd_strings),
    ):
        p = sub.add_parser(name, help=help_)
        p.add_argument("dump", type=Path)
        p.set_defaults(func=fn)

    p = sub.add_parser("fields", help="show offline fields for type substring")
    p.add_argument("dump", type=Path)
    p.add_argument("needle")
    p.set_defaults(func=_cmd_fields)

    p = sub.add_parser("find", help="search field names / screen strings")
    p.add_argument("dump", type=Path)
    p.add_argument("needle")
    p.set_defaults(func=_cmd_find)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
