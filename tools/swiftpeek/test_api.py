#!/usr/bin/env python3
"""Smoke tests for the SwiftPeek read API (no device required)."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from swiftpeek.api import FieldCatalog, PeekSession, annotate_dump  # noqa: E402
from swiftpeek.paths import DEFAULT_CATALOG  # noqa: E402


SAMPLE = {
    "tool_version": "0.3.6",
    "milestone": 2,
    "message": "test",
    "nodes": [
        {
            "type": "MusicApplication.MiniPlayerViewController",
            "role": "scan_controller",
            "screen_strings": ["kiss me", "Ariana Grande"],
        },
        {
            "type": "MusicApplication.NowPlayingContentView",
            "role": "scan_view",
        },
        {
            "type": (
                "MusicApplication.SearchViewController"
                "<MusicApplication.SearchLandingViewController>"
            ),
            "role": "scan_controller",
            "screen_strings": ["Search"],
        },
    ],
}


class ReadAPITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not DEFAULT_CATALOG.is_file():
            raise unittest.SkipTest(f"missing catalog {DEFAULT_CATALOG}")
        cls.catalog = FieldCatalog(DEFAULT_CATALOG)

    def test_catalog_nonempty(self):
        self.assertGreater(len(self.catalog), 1000)

    def test_annotate_matches(self):
        out = annotate_dump(SAMPLE, self.catalog)
        info = out["offline_annotate"]
        self.assertEqual(info["matched_nodes"], 3)
        self.assertEqual(info["api_version"], "0.4.0")
        mini = out["nodes"][0]
        self.assertTrue(mini["offline_fields"])
        names = {f["name"] for f in mini["offline_fields"]}
        self.assertIn("artworkView", names)

    def test_session_find_artwork(self):
        sess = PeekSession(SAMPLE, self.catalog)
        hits = sess.find("artwork")
        self.assertTrue(hits)
        self.assertTrue(any(h.source == "field" for h in hits))

    def test_session_summary(self):
        sess = PeekSession(SAMPLE, self.catalog)
        s = sess.summary()
        self.assertEqual(s["nodes"], 3)
        self.assertEqual(s["with_strings"], 2)
        self.assertGreaterEqual(s["with_fields"], 2)

    def test_generic_type_strip(self):
        hit = self.catalog.lookup(
            "MusicApplication.SearchViewController"
            "<MusicApplication.SearchLandingViewController>"
        )
        self.assertIsNotNone(hit)
        self.assertTrue(str(hit["key"]).startswith("MusicApplication.SearchViewController"))

    def test_roundtrip_file(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "dump.json"
            p.write_text(json.dumps(SAMPLE))
            sess = PeekSession(p, self.catalog)
            self.assertEqual(sess.summary()["matched_nodes"], 3)


if __name__ == "__main__":
    unittest.main()
