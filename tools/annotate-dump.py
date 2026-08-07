#!/usr/bin/env python3
"""Join a SwiftPeek live dump JSON with offline field layouts.

Thin wrapper around the Phase 2 read API (`tools/swiftpeek`).

Usage:
  python3 tools/annotate-dump.py path/to/Music_....json
  python3 tools/annotate-dump.py dump.json -o annotated.json
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from swiftpeek.cli import main


if __name__ == "__main__":
    # Map legacy argv → `swiftpeek annotate …`
    argv = ["annotate", *sys.argv[1:]]
    raise SystemExit(main(argv))
