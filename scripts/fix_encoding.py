"""Fix mojibake (Windows-1252 misread as UTF-8) in Dart source files."""
import sys

REPLACEMENTS = [
    # mojibake          correct
    ("\u00e2\u20ac\u201c", "\u2014"),   # â€" → — (em dash)
    ("\u00e2\u20ac\u00a2", "\u2022"),   # â€¢ → • (bullet)
    ("\u00e2\u2514\u20ac", "\u2500"),   # â"€ → ─ (box drawing)
    ("\u00f0\u0178\u2018\u2039", "\U0001F44B"),  # ðŸ'‹ → 👋 (wave emoji)
]

def fix_file(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    original = content
    for bad, good in REPLACEMENTS:
        content = content.replace(bad, good)

    if content != original:
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"Fixed: {path}")
    else:
        print(f"No changes needed: {path}")

if __name__ == "__main__":
    files = sys.argv[1:] or [
        r"d:\start_track\must_startrack\lib\features\feed\screens\home_feed_screen.dart"
    ]
    for f in files:
        fix_file(f)
