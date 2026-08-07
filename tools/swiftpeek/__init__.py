"""SwiftPeek host-side read API — annotate live dumps with offline field layouts.

Phase 2 substrate surface. No live FOVO; safe to use with 0.3.6 device dumps.
"""

from .api import FieldCatalog, PeekSession, annotate_dump, load_dump

__all__ = [
    "FieldCatalog",
    "PeekSession",
    "annotate_dump",
    "load_dump",
]

__version__ = "0.4.0"
