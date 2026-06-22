#!/usr/bin/env python3
"""
Subset the Phosphor icon font to only the glyphs üsgu actually uses.

Why: the full Phosphor.woff2 is ~147 KB (~1,500 glyphs) but the app renders only
a couple dozen icons. Shipping the full font on every cold start is wasteful, so
we ship a subset that contains exactly the used glyphs.

This is the REGENERATE mechanism. Re-run it whenever you add or remove a `ph-…`
icon class anywhere in the app — it re-derives the used set from the source tree,
so there is no hand-maintained list:

    pip install --user fonttools brotli      # one-time prerequisite
    python3 script/subset_phosphor.py

Inputs:
  - vendor/phosphor/Phosphor.woff2        full master font — NEVER edit/subset it
  - app/assets/stylesheets/phosphor.css   class -> codepoint map
  - every tracked source file             which `ph-…` classes are referenced

Output:
  - app/assets/fonts/Phosphor.woff2       subset, served + referenced by the CSS

Note: we deliberately do NOT trim phosphor.css (no build step — see BACKLOG), so
it keeps all ~1,500 class definitions. A `ph-…` class whose glyph isn't in the
subset renders as a blank box, which is exactly why this must be re-run after
adding an icon. The script fails loudly if a used class has no codepoint.
"""
import re
import subprocess
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CSS = ROOT / "app/assets/stylesheets/phosphor.css"
MASTER = ROOT / "vendor/phosphor/Phosphor.woff2"
OUT = ROOT / "app/assets/fonts/Phosphor.woff2"

CSS_REL = "app/assets/stylesheets/phosphor.css"
TOKEN = re.compile(r"ph-[a-z0-9]+(?:-[a-z0-9]+)*")
# .ph.ph-bell:before { content: "\e0ce"; }  (selector and content may span lines)
DEF = re.compile(r"\.ph\.(ph-[a-z0-9-]+):before\s*\{\s*content:\s*\"\\([0-9a-fA-F]+)\"")


def main():
    if not MASTER.exists():
        sys.exit(f"missing master font: {MASTER} (the full, un-subset Phosphor.woff2)")

    # 1. class -> codepoint, parsed straight from the CSS.
    defs = {m.group(1): int(m.group(2), 16) for m in DEF.finditer(CSS.read_text())}
    if not defs:
        sys.exit(f"parsed zero glyph definitions from {CSS_REL} — did the format change?")

    # 2. which ph- classes the app references (every tracked file except the CSS).
    #    Intersecting with `defs` keeps only real icon classes, so stray matches
    #    like "ph-5" or genre slugs containing "ph-" fall away on their own.
    files = subprocess.check_output(["git", "ls-files"], cwd=ROOT).decode().splitlines()
    used = set()
    for rel in files:
        if rel == CSS_REL:
            continue
        try:
            text = (ROOT / rel).read_text(errors="ignore")
        except (OSError, UnicodeDecodeError):
            continue
        used.update(tok for tok in TOKEN.findall(text) if tok in defs)

    if not used:
        sys.exit("found no used `ph-…` icon classes — refusing to build an empty font")

    codepoints = sorted(defs[c] for c in used)
    unicodes = ",".join(f"U+{cp:04X}" for cp in codepoints)

    print(f"used icons: {len(used)}")
    for cls in sorted(used):
        print(f"  {cls:32} U+{defs[cls]:04X}")

    before = MASTER.stat().st_size

    # 3. subset. Access is by codepoint (CSS `content`), so we drop layout
    #    features (ligatures) and hinting — none of it is reachable.
    subprocess.check_call([
        sys.executable, "-m", "fontTools.subset", str(MASTER),
        f"--unicodes={unicodes}",
        "--layout-features=",
        "--no-hinting",
        "--desubroutinize",
        "--flavor=woff2",
        f"--output-file={OUT}",
    ])

    # 4. verify every requested codepoint actually survived into the subset.
    from fontTools.ttLib import TTFont
    cmap = set()
    with TTFont(OUT) as font:
        for table in font["cmap"].tables:
            cmap.update(table.cmap.keys())
    missing = [c for c in codepoints if c not in cmap]
    if missing:
        sys.exit("subset is MISSING codepoints: " + ", ".join(f"U+{c:04X}" for c in missing))

    after = OUT.stat().st_size
    print(f"\nwrote {OUT.relative_to(ROOT)}")
    print(f"{before:,} -> {after:,} bytes ({100 * after / before:.1f}% of original)")


if __name__ == "__main__":
    main()
