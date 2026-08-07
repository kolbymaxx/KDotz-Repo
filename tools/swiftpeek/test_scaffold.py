#!/usr/bin/env python3
"""Tests for SwiftPeek tweak target ranking + Theos scaffold."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from swiftpeek.api import FieldCatalog, PeekSession  # noqa: E402
from swiftpeek.paths import DEFAULT_CATALOG  # noqa: E402
from swiftpeek.scaffold import (  # noqa: E402
    generate_tweak_x,
    rank_targets,
    write_scaffold,
)


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
        # Controllers with screen strings should outrank bare views without.
        top = ranked[0]
        self.assertIn("MusicApplication", top.type_name)
        self.assertGreater(top.score, 0)

    def test_generate_tweak_x_single_hook(self):
        ranked = rank_targets(self.sess)
        src = generate_tweak_x("PeekMusicTweak", ranked, filter_substr="MiniPlayer")
        self.assertEqual(src.count("%hook UIViewController"), 1)
        self.assertIn("MiniPlayerViewController", src)
        self.assertIn("PeekClassMatches", src)
        self.assertIn("viewDidAppear", src)
        self.assertNotIn("%hook UIViewController\n%hook", src)

    def test_write_scaffold_files(self):
        with tempfile.TemporaryDirectory() as td:
            root = write_scaffold(
                self.sess,
                Path(td) / "MyTweak",
                name="MyMusicTweak",
                filter_substr="MiniPlayer",
            )
            self.assertTrue((root / "Makefile").is_file())
            self.assertTrue((root / "control").is_file())
            self.assertTrue((root / "TARGETS.md").is_file())
            self.assertTrue((root / "src" / "Tweak.x").is_file())
            self.assertTrue((root / "MyMusicTweak.plist").is_file())
            makefile = (root / "Makefile").read_text()
            self.assertIn("TWEAK_NAME = MyMusicTweak", makefile)
            self.assertIn("THEOS_PACKAGE_SCHEME ?= rootless", makefile)
            control = (root / "control").read_text()
            self.assertIn("Package: com.kolby.peekmusic", control)
            tweak = (root / "src" / "Tweak.x").read_text()
            self.assertIn("MiniPlayerViewController", tweak)
            targets = (root / "TARGETS.md").read_text()
            self.assertIn("SwiftPeek tweak targets", targets)


if __name__ == "__main__":
    unittest.main()
