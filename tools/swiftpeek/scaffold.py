"""Generate Theos tweak scaffolds + ranked targets from annotated dumps.

Phase 3+ substrate surface: dump → ranked Music types → starter Theos project
with real @try valueForKey: stubs from offline fields.
Follows Music27's safe pattern — hook UIKit bases, filter by class_getName.
No live FOVO; addresses from dumps are not stable across launches.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .api import PeekSession


# Field name / type hints that usually matter for UI tweaks.
_INTERESTING = re.compile(
    r"(button|label|artwork|title|action|stack|bar|player|queue|view|gesture|menu|"
    r"image|header|footer|tab|lyric|transport|control|chrome|dock)",
    re.I,
)

# Prefer these for first KVC experiments (likely ObjC UI objects).
_KVC_PREFERRED = re.compile(
    r"(label|button|artwork|image|stack|bar|view|control|header|title)",
    re.I,
)


@dataclass
class TargetScore:
    type_name: str
    objc_class: str
    role: str
    score: int
    screen_strings: list[str]
    interesting_fields: list[str]
    field_count: int
    field_rows: list[dict[str, str]] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "type": self.type_name,
            "objc_class": self.objc_class,
            "role": self.role,
            "score": self.score,
            "field_count": self.field_count,
            "screen_strings": list(self.screen_strings),
            "interesting_fields": list(self.interesting_fields),
            "field_rows": list(self.field_rows),
        }

    @property
    def is_view(self) -> bool:
        role = (self.role or "").lower()
        if "view" in role and "controller" not in role:
            return True
        short = _short(self.type_name)
        return short.endswith("View") and not short.endswith("ViewController")


def _short(name: str) -> str:
    return name.rsplit(".", 1)[-1].split("<", 1)[0]


def rank_targets(session: PeekSession, limit: int = 20) -> list[TargetScore]:
    """Score dump nodes for tweakability (Music types + strings + field hints)."""
    seen: dict[str, TargetScore] = {}
    for node in session.nodes:
        type_name = (
            node.get("offline_type")
            or node.get("type")
            or node.get("objc_class")
            or "?"
        )
        objc = node.get("objc_class") or type_name
        strings = [str(s) for s in (node.get("screen_strings") or []) if s]
        fields = node.get("offline_fields") or []
        interesting: list[str] = []
        rows: list[dict[str, str]] = []
        for f in fields:
            name = str(f.get("name") or "")
            typ = str(f.get("type") or "")
            if _INTERESTING.search(name) or _INTERESTING.search(typ):
                interesting.append(name)
                rows.append({"name": name, "type": typ})
        score = len(strings) * 3 + len(interesting) * 2 + min(len(fields), 20)
        if type_name.startswith("MusicApplication.") or "Music" in type_name:
            score += 10
        role = str(node.get("role") or "")
        if "controller" in role:
            score += 4
        prev = seen.get(type_name)
        if prev is None or score > prev.score:
            seen[type_name] = TargetScore(
                type_name=type_name,
                objc_class=str(objc),
                role=role,
                score=score,
                screen_strings=strings[:12],
                interesting_fields=interesting[:16],
                field_count=len(fields),
                field_rows=rows[:16],
            )
    ranked = sorted(seen.values(), key=lambda t: (-t.score, t.type_name))
    return ranked[:limit]


def format_targets(targets: list[TargetScore]) -> str:
    lines = [
        "# SwiftPeek tweak targets (ranked)",
        "",
        "Use offline field names with `@try { id x = [self valueForKey:@\"…\"]; }`.",
        "Never FOVO-walk Music hosts on device. Addresses are not stable.",
        "",
    ]
    for i, t in enumerate(targets, 1):
        kind = "view" if t.is_view else "controller"
        lines.append(f"## {i}. {t.type_name}  (score {t.score}, {kind})")
        lines.append(f"- objc_class: `{t.objc_class}`")
        lines.append(f"- role: `{t.role}` · fields: {t.field_count}")
        if t.screen_strings:
            lines.append(
                f"- screen: {', '.join(repr(s) for s in t.screen_strings[:8])}"
            )
        if t.field_rows:
            lines.append("- KVC candidates:")
            for row in t.field_rows[:12]:
                lines.append(f"  - `{row['name']}` : `{row['type']}`")
        elif t.interesting_fields:
            lines.append(
                f"- interesting: {', '.join(t.interesting_fields[:12])}"
            )
        lines.append("")
    return "\n".join(lines)


def _sanitize_pkg(name: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "", name)
    if not s:
        s = "PeekTweak"
    if s[0].isdigit():
        s = "T" + s
    return s


def _select_targets(
    targets: list[TargetScore],
    filter_substr: str | None,
    max_hooks: int = 5,
) -> list[TargetScore]:
    if filter_substr:
        n = filter_substr.lower()
        chosen = [
            t
            for t in targets
            if n in t.type_name.lower() or n in t.objc_class.lower()
        ]
        if chosen:
            return chosen[:max_hooks]
    return targets[:max_hooks]


def _kvc_fields(t: TargetScore, limit: int = 4) -> list[dict[str, str]]:
    rows = list(t.field_rows) if t.field_rows else [
        {"name": n, "type": "?"} for n in t.interesting_fields
    ]
    preferred = [
        r for r in rows if _KVC_PREFERRED.search(r.get("name") or "")
    ]
    ordered = preferred + [r for r in rows if r not in preferred]
    # Skip Swift private / lazy storage noise for first stubs.
    out = []
    for r in ordered:
        name = r.get("name") or ""
        if name.startswith("$") or "lazy_storage" in name:
            continue
        out.append(r)
        if len(out) >= limit:
            break
    return out


def _kvc_block(indent: str, fields: list[dict[str, str]]) -> list[str]:
    if not fields:
        return [f"{indent}// TODO: no offline field candidates — try `swiftpeek catalog fields <Type>`"]
    lines = [f"{indent}@try {{"]
    for r in fields:
        name = r["name"]
        typ = r.get("type") or "?"
        lines.append(f'{indent}    id {name} = [self valueForKey:@"{name}"]; // {typ}')
        lines.append(
            f'{indent}    if ({name}) NSLog(@"  {name}=%@", {name});'
        )
    lines += [
        f"{indent}}} @catch (__unused NSException *ex) {{",
        f'{indent}    NSLog(@"  KVC miss");',
        f"{indent}}}",
    ]
    return lines


def generate_tweak_x(
    tweak_name: str,
    targets: list[TargetScore],
    *,
    filter_substr: str | None = None,
) -> str:
    """Emit UIViewController and/or UIView hooks with class-name filters + KVC stubs."""
    chosen = _select_targets(targets, filter_substr)
    if not chosen:
        chosen = targets[:3]

    controllers = [t for t in chosen if not t.is_view]
    views = [t for t in chosen if t.is_view]
    # Always keep at least one VC hook if we have mixed/empty.
    if not controllers and not views:
        controllers = chosen

    body = [
        "// Auto-generated by SwiftPeek scaffold — starting point only.",
        "// Pattern matches Music27: hook UIKit bases, filter by class name.",
        "// Dump addresses are NOT stable — use class + offline field names.",
        "// Keep SwiftPeek Dump Field Meta OFF on device.",
        "#import <UIKit/UIKit.h>",
        "#import <objc/runtime.h>",
        "#import <string.h>",
        "",
        "static BOOL PeekClassMatches(Class cls, const char *needle) {",
        "    if (!cls || !needle) return NO;",
        "    const char *n = class_getName(cls);",
        "    return n && strstr(n, needle) != NULL;",
        "}",
        "",
    ]

    for t in chosen:
        token = _short(t.type_name)
        kind = "view" if t.is_view else "controller"
        body.append(f"// Target ({kind}): {t.type_name}")
        if t.screen_strings:
            body.append(f"// screen: {', '.join(t.screen_strings[:6])}")
        for r in _kvc_fields(t, 6):
            body.append(f"// field: {r['name']} : {r.get('type')}")
        body.append("")

    if controllers:
        body += [
            "%hook UIViewController",
            "- (void)viewDidAppear:(BOOL)animated {",
            "    %orig;",
            "    Class cls = object_getClass(self);",
        ]
        for t in controllers:
            token = _short(t.type_name)
            fields = _kvc_fields(t)
            body += [
                f'    if (PeekClassMatches(cls, "{token}")) {{',
                f'        NSLog(@"[{tweak_name}] {token} %p", self);',
            ]
            body += _kvc_block("        ", fields)
            body.append("    }")
        body += [
            "}",
            "%end",
            "",
        ]

    if views:
        for t in views:
            token = _short(t.type_name)
            safe = re.sub(r"[^A-Za-z0-9]", "_", token)
            body.append(f"static char kPeekOnce_{safe};")
        body.append("")
        body += [
            "%hook UIView",
            "- (void)didMoveToWindow {",
            "    %orig;",
            "    if (!self.window) return;",
            "    Class cls = object_getClass(self);",
        ]
        for t in views:
            token = _short(t.type_name)
            safe = re.sub(r"[^A-Za-z0-9]", "_", token)
            fields = _kvc_fields(t)
            body += [
                f'    if (PeekClassMatches(cls, "{token}")) {{',
                f"        if (!objc_getAssociatedObject(self, &kPeekOnce_{safe})) {{",
                f"            objc_setAssociatedObject(self, &kPeekOnce_{safe}, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);",
                f'            NSLog(@"[{tweak_name}] {token} %p", self);',
            ]
            for line in _kvc_block("            ", fields):
                body.append(line)
            body += [
                "        }",
                "    }",
            ]
        body += [
            "}",
            "%end",
            "",
        ]

    return "\n".join(body)


def write_scaffold(
    session: PeekSession,
    out_dir: Path,
    *,
    name: str = "PeekMusicTweak",
    bundle_id: str = "com.kolby.peekmusic",
    filter_substr: str | None = None,
    limit: int = 12,
) -> Path:
    """Write a minimal Theos project under out_dir. Returns the project root."""
    tweak = _sanitize_pkg(name)
    pkg = bundle_id if bundle_id else f"com.kolby.{tweak.lower()}"
    root = Path(out_dir)
    src = root / "src"
    src.mkdir(parents=True, exist_ok=True)

    targets = rank_targets(session, limit=limit)
    (root / "TARGETS.md").write_text(format_targets(targets), encoding="utf-8")
    (root / "src" / "Tweak.x").write_text(
        generate_tweak_x(tweak, targets, filter_substr=filter_substr),
        encoding="utf-8",
    )

    (root / f"{tweak}.plist").write_text(
        "{\n"
        "\tFilter = {\n"
        "\t\tBundles = (\n"
        '\t\t\t"com.apple.Music"\n'
        "\t\t);\n"
        "\t\tExecutables = (\n"
        '\t\t\t"Music"\n'
        "\t\t);\n"
        "\t};\n"
        "}\n",
        encoding="utf-8",
    )

    (root / "Makefile").write_text(
        "\n".join(
            [
                "TARGET := iphone:clang:16.5:15.0",
                "ARCHS = arm64 arm64e",
                "INSTALL_TARGET_PROCESSES = Music",
                "THEOS_PACKAGE_SCHEME ?= rootless",
                "",
                "include $(THEOS)/makefiles/common.mk",
                "",
                f"TWEAK_NAME = {tweak}",
                f"{tweak}_FILES = src/Tweak.x",
                f"{tweak}_CFLAGS = -fobjc-arc -Wno-unused-variable",
                f"{tweak}_FRAMEWORKS = UIKit Foundation",
                "",
                "include $(THEOS_MAKE_PATH)/tweak.mk",
                "",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    (root / "control").write_text(
        "\n".join(
            [
                f"Package: {pkg}",
                f"Name: {tweak}",
                "Depends: mobilesubstrate",
                "Version: 0.0.1",
                "Architecture: iphoneos-arm64",
                "Description: Scaffold from SwiftPeek dump — Music-only. Edit src/Tweak.x.",
                "Maintainer: Kolby",
                "Author: Kolby",
                "Section: Tweaks",
                "",
            ]
        ),
        encoding="utf-8",
    )

    (root / "README.md").write_text(
        "\n".join(
            [
                f"# {tweak}",
                "",
                "Scaffold generated by SwiftPeek from a live Music dump + offline field catalog.",
                "",
                "## Build (Dopamine / rootless)",
                "",
                "Needs Theos + an iPhoneOS SDK (same as Music27). If `common.mk` is missing:",
                "",
                "```bash",
                "git clone --recursive https://github.com/theos/theos.git ~/theos",
                "# put iPhoneOS*.sdk under ~/theos/sdks/",
                "export THEOS=~/theos",
                "make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless",
                "```",
                "",
                "Edit Logos with: `open -t src/Tweak.x` (or VS Code).",
                "",
                "## Next",
                "",
                "1. Read `TARGETS.md` — pick a high-score type + KVC candidates.",
                "2. Edit `src/Tweak.x` — `@try` / `valueForKey:` stubs are pre-filled.",
                "3. Browse more fields without a dump:",
                "   `PYTHONPATH=tools python3 -m swiftpeek catalog fields MiniPlayer`",
                "4. Keep SwiftPeek **Dump Field Meta** off on device while developing.",
                "",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    return root
