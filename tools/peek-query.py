#!/usr/bin/env python3
"""Query an annotated SwiftPeek dump.

Thin wrapper around the Phase 2 read API (`tools/swiftpeek`).

Examples:
  python3 tools/peek-query.py ~/Downloads/annotated.json summary
  python3 tools/peek-query.py ~/Downloads/annotated.json fields MiniPlayer
  python3 tools/peek-query.py ~/Downloads/annotated.json find artwork
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from swiftpeek.cli import main


if __name__ == "__main__":
    # Legacy: peek-query.py DUMP CMD [ARG]
    # New:    swiftpeek CMD DUMP [ARG]
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    dump, cmd, *rest = args
    argv = [cmd, dump, *rest]
    raise SystemExit(main(argv))
