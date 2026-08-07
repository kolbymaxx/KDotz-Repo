#!/usr/bin/env python3
"""Tests for SwiftPeek tweak target ranking + Theos scaffold."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
sys.path.insert(0, str(ROOT))

from swiftpeek.api import FieldCatalog, PeekSession  # noqa: E402
from swiftpeek.paths import DEFAULT_CATALOG  # noqa: E402
from swiftpeek.scaffold import (  # noqa: E402
    generate_tweak_x,
    rank_targets,
    write_scaffold,
)

FIXTURE = REPO / "SwiftPeek" / "docs" / "fixtures" / "Music_sample.json"

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


class ScaffoldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not DEFAULT_CATALOG.is_file():
            raise unittest.SkipTest(f"missing catalog {DEFAULT_CATALOG}")
        cls.catalog = FieldCatalog(DEFAULT_CATALOG)
        cls.sess = PeekSession(SAMPLE, cls.catalog)

    def test_rank_prefers_miniplayer(self):
        ranked = rank_targets(self.sess, limit=10)
        self.assertTrue(ranked)
        names = [t.type_name for t in ranked]
        self.assertTrue(any("MiniPlayer" in n for n in names))
        top = ranked[0]
        self.assertIn("MusicApplication", top.type_name)
        self.assertGreater(top.score, 0)

    def test_generate_tweak_x_kvc_stubs(self):
        ranked = rank_targets(self.sess)
        src = generate_tweak_x("PeekMusicTweak", ranked, filter_substr="MiniPlayer")
        self.assertEqual(src.count("%hook UIViewController"), 1)
        self.assertIn("MiniPlayerViewController", src)
        self.assertIn("PeekClassMatches", src)
        self.assertIn("valueForKey:", src)
        self.assertIn("@try", src)
        self.assertIn("artworkView", src)

    def test_generate_includes_view_hook(self):
        ranked = rank_targets(self.sess)
        src = generate_tweak_x("PeekMusicTweak", ranked)
        self.assertIn("%hook UIViewController", src)
        self.assertIn("%hook UIView", src)
        self.assertIn("NowPlayingContentView", src)
        self.assertIn("didMoveToWindow", src)

    def test_write_scaffold_files(self):
        with tempfile.TemporaryDirectory() as td:
            root = write_scaffold(
                self.sess,
                Path(td) / "MyTweak",
                name="MyMusicTweak",
                filter_substr="MiniPlayer",
            )
            self.assertTrue((root / "Makefile").is_file())
            self.assertTrue((root / "TARGETS.md").is_file())
            tweak = (root / "src" / "Tweak.x").read_text()
            self.assertIn("valueForKey:", tweak)
            targets = (root / "TARGETS.md").read_text()
            self.assertIn("KVC candidates", targets)

    def test_fixture_roundtrip(self):
        if not FIXTURE.is_file():
            self.skipTest(f"missing fixture {FIXTURE}")
        sess = PeekSession(FIXTURE, self.catalog)
        s = sess.summary()
        self.assertEqual(s["nodes"], 5)
        self.assertEqual(s["matched_nodes"], 5)
        ranked = rank_targets(sess, limit=5)
        self.assertTrue(any("MiniPlayer" in t.type_name for t in ranked))


class CatalogCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not DEFAULT_CATALOG.is_file():
            raise unittest.SkipTest(f"missing catalog {DEFAULT_CATALOG}")
        cls.catalog = FieldCatalog(DEFAULT_CATALOG)

    def test_catalog_search_types(self):
        rows = self.catalog.search_types("MiniPlayer")
        self.assertTrue(rows)
        self.assertTrue(any("MiniPlayer" in r["type"] for r in rows))

    def test_catalog_find_artwork(self):
        hits = self.catalog.find_fields("artwork", limit=20)
        self.assertTrue(hits)
        self.assertTrue(any("artwork" in h["name"].lower() for h in hits))


if __name__ == "__main__":
    unittest.main()
