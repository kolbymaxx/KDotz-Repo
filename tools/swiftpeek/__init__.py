"""SwiftPeek host-side read API — annotate live dumps with offline field layouts.

Phase 2: read/annotate/query. Phase 3: ranked targets + Theos scaffold.
Phase 3.1: catalog browse (no dump) + richer KVC scaffold stubs.
No live FOVO; safe to use with 0.3.6 device dumps.
"""

from .api import FieldCatalog, PeekSession, annotate_dump, load_dump
from .scaffold import TargetScore, format_targets, generate_tweak_x, rank_targets, write_scaffold

__all__ = [
    "FieldCatalog",
    "PeekSession",
    "TargetScore",
    "annotate_dump",
    "format_targets",
    "generate_tweak_x",
    "load_dump",
    "rank_targets",
    "write_scaffold",
]

__version__ = "0.6.0"
