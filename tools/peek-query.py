#!/usr/bin/env python3
"""Query an annotated SwiftPeek dump (after annotate-dump.py).

Examples:
  python3 tools/peek-query.py ~/Downloads/annotated.json summary
  python3 tools/peek-query.py ~/Downloads/annotated.json types
  python3 tools/peek-query.py ~/Downloads/annotated.json strings
  python3 tools/peek-query.py ~/Downloads/annotated.json fields MiniPlayer
  python3 tools/peek-query.py ~/Downloads/annotated.json find artwork
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def cmd_summary(dump: dict) -> None:
    nodes = dump.get("nodes") or []
    ann = dump.get("offline_annotate") or {}
    print(f"tool_version: {dump.get('tool_version')}")
    print(f"milestone:    {dump.get('milestone')}")
    print(f"message:      {dump.get('message')}")
    print(f"nodes:        {len(nodes)}")
    if ann:
        print(
            f"offline:      {ann.get('matched_nodes')}/{ann.get('total_nodes')} "
            f"matched ({ann.get('catalog_types')} catalog types)"
        )
    with_fields = sum(1 for n in nodes if n.get("offline_fields"))
    with_strings = sum(1 for n in nodes if n.get("screen_strings"))
    print(f"with_fields:  {with_fields}")
    print(f"with_strings: {with_strings}")


def cmd_types(dump: dict) -> None:
    for n in dump.get("nodes") or []:
        t = n.get("offline_type") or n.get("type") or n.get("objc_class") or "?"
        nf = len(n.get("offline_fields") or [])
        ns = len(n.get("screen_strings") or [])
        role = n.get("role") or ""
        print(f"{nf:3d}f {ns:2d}s  {role:16} {t}")


def cmd_strings(dump: dict) -> None:
    for n in dump.get("nodes") or []:
        ss = n.get("screen_strings") or []
        if not ss:
            continue
        t = n.get("type") or "?"
        print(f"## {t}")
        for s in ss:
            print(f"  - {s}")
        print()


def cmd_fields(dump: dict, needle: str) -> None:
    needle_l = needle.lower()
    hits = 0
    for n in dump.get("nodes") or []:
        t = n.get("offline_type") or n.get("type") or ""
        if needle_l not in t.lower() and needle_l not in (n.get("objc_class") or "").lower():
            continue
        hits += 1
        print(f"## {t}")
        for f in n.get("offline_fields") or []:
            print(f"  [{f.get('index')}] {f.get('name')} : {f.get('type')}")
        print()
    if not hits:
        print(f"no nodes matching {needle!r}", file=sys.stderr)


def cmd_find(dump: dict, needle: str) -> None:
    needle_l = needle.lower()
    for n in dump.get("nodes") or []:
        t = n.get("offline_type") or n.get("type") or "?"
        for f in n.get("offline_fields") or []:
            name = str(f.get("name") or "")
            typ = str(f.get("type") or "")
            if needle_l in name.lower() or needle_l in typ.lower():
                print(f"{t}.{name} : {typ}")
        for s in n.get("screen_strings") or []:
            if needle_l in str(s).lower():
                print(f"{t} screen_string={s!r}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("dump", type=Path)
    ap.add_argument(
        "command",
        choices=["summary", "types", "strings", "fields", "find"],
    )
    ap.add_argument("arg", nargs="?", help="substring for fields/find")
    args = ap.parse_args()
    if not args.dump.is_file():
        print(f"missing {args.dump}", file=sys.stderr)
        return 1
    dump = load(args.dump)
    if args.command == "summary":
        cmd_summary(dump)
    elif args.command == "types":
        cmd_types(dump)
    elif args.command == "strings":
        cmd_strings(dump)
    elif args.command == "fields":
        if not args.arg:
            print("fields requires a type substring", file=sys.stderr)
            return 1
        cmd_fields(dump, args.arg)
    elif args.command == "find":
        if not args.arg:
            print("find requires a name substring", file=sys.stderr)
            return 1
        cmd_find(dump, args.arg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
