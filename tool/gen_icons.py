"""Generate app/lib/design/app_icons.g.dart from the reference HTML.

The design kit draws every icon as an inline SVG. This script collects the
unique ones and writes them out as Dart data, so the app's icons are exactly
the ones in the design and never drift from it.

Run from the repository root:  python tool/gen_icons.py
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "design" / "reference-html"
OUT = ROOT / "app" / "lib" / "design" / "app_icons.g.dart"

# Stable names, keyed by the icon's markup. A new icon in the kit fails the
# build until it is named here.
NAMES = {
    '<path d="M5 15a7 7 0 0 1 14 0"></path><circle cx="5" cy="17" r="1.6" fill="currentColor"></circle><circle cx="19" cy="17" r="1.6" fill="currentColor"></circle>': "logo",
    '<circle cx="12" cy="12" r="2"></circle><path d="M7.8 7.8a6 6 0 0 0 0 8.4M16.2 7.8a6 6 0 0 1 0 8.4M4.9 4.9a10 10 0 0 0 0 14.2M19.1 4.9a10 10 0 0 1 0 14.2"></path>': "nearby",
    '<rect x="5" y="11" width="14" height="10" rx="2"></rect><path d="M8 11V7a4 4 0 0 1 8 0v4"></path>': "lock",
    '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"></path><path d="M14 3v5h5"></path>': "file",
    '<circle cx="11" cy="11" r="7"></circle><path d="m20 20-3.5-3.5"></path>': "search",
    '<circle cx="10" cy="8" r="4"></circle><path d="M2 21a8 8 0 0 1 13-6M19 14v6M16 17h6"></path>': "personAdd",
    '<path d="m9 6 6 6-6 6"></path>': "chevronRight",
    '<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6l-8-3Z"></path><path d="m9 12 2 2 4-4"></path>': "verified",
    '<circle cx="12" cy="13" r="8"></circle><path d="M12 9v4l3 2M9 2h6"></path>': "timer",
    '<path d="M6 3h12v18l-6-4-6 4V3Z"></path>': "bookmark",
    '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12Z"></path>': "chat",
    '<path d="M5 9h14M5 15h14M10 4 8 20M16 4l-2 16"></path>': "hash",
    '<circle cx="12" cy="8" r="4"></circle><path d="M4 21a8 8 0 0 1 16 0"></path>': "person",
    '<path d="m15 6-6 6 6 6"></path>': "back",
    '<rect x="3" y="3" width="7" height="7"></rect><rect x="14" y="3" width="7" height="7"></rect><rect x="3" y="14" width="7" height="7"></rect><path d="M14 14h3v3h-3zM20 14v3M14 20h3M20 20h1"></path>': "qr",
    '<path d="M4 8h3l2-3h6l2 3h3v11H4V8Z"></path><circle cx="12" cy="13" r="3.5"></circle>': "camera",
    '<path d="M6 8a8 8 0 0 1 0 8M10 5a12 12 0 0 1 0 14M14 8a8 8 0 0 1 0 8"></path>': "tap",
    '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"></path>': "link",
    '<path d="m5 12 5 5 9-10"></path>': "check",
    '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a1 1 0 0 1-1 1A16 16 0 0 1 4 5a1 1 0 0 1 1-1Z"></path>': "phone",
    '<circle cx="5" cy="12" r="1"></circle><circle cx="12" cy="12" r="1"></circle><circle cx="19" cy="12" r="1"></circle>': "more",
    '<path d="m2 12 4 4 8-9M11 16l1 1 9-10"></path>': "read",
    '<path d="M8 5v14l11-7L8 5Z"></path>': "play",
    '<path d="M12 5v14M5 12h14"></path>': "plus",
    '<rect x="9" y="3" width="6" height="11" rx="3"></rect><path d="M5 11a7 7 0 0 0 14 0M12 18v3"></path>': "mic",
    '<path d="M3 10v4h3l8 4V6L6 10H3ZM17 9a4 4 0 0 1 0 6"></path>': "megaphone",
    '<path d="M4 9v6h4l5 4V5L8 9H4ZM16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11"></path>': "speaker",
    '<circle cx="9" cy="8" r="3.5"></circle><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14.5a6 6 0 0 1 3.5 5.5"></path>': "people",
    '<path d="M12 17v5M8 3h8l-1 6 3 4H6l3-4-1-6Z"></path>': "pin",
    '<path d="M9 7 4 12l5 5M4 12h10a6 6 0 0 1 6 6v1"></path>': "reply",
    '<path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10Z"></path>': "heart",
    '<path d="M6 6l12 12M18 6 6 18"></path>': "close",
    '<rect x="3" y="5" width="18" height="14" rx="2"></rect><circle cx="9" cy="10" r="1.5"></circle><path d="m4 18 5-5 4 4 3-3 4 4"></path>': "photo",
    '<path d="M5 20V10M12 20V4M19 20v-7"></path>': "poll",
    '<path d="M12 21s-6-5.5-6-11a6 6 0 0 1 12 0c0 5.5-6 11-6 11Z"></path><circle cx="12" cy="10" r="2"></circle>': "location",
    '<path d="M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"></path><circle cx="12" cy="19.5" r="1"></circle>': "wifi",
    '<rect x="3" y="6" width="13" height="12" rx="2"></rect><path d="m16 10 5-3v10l-5-3"></path>': "video",
    '<path d="M9 5v14M15 5v14"></path>': "pause",
    '<rect x="9" y="3" width="6" height="11" rx="3"></rect><path d="M5 11a7 7 0 0 0 14 0M12 18v3M4 4l16 16"></path>': "micOff",
    '<path d="m7 7 10 10-5 5V2l5 5L7 17"></path>': "bluetooth",
    '<path d="M5 21 12 7l7 14M8.5 15h7M8 4a6 6 0 0 1 8 0"></path>': "antenna",
    '<circle cx="12" cy="12" r="9"></circle><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"></path>': "globe",
    '<path d="M12 3 2 20h20L12 3Z"></path><path d="M12 10v4M12 17v.5"></path>': "warning",
    '<path d="M3 12V4h8l10 10-8 8L3 12Z"></path><circle cx="7.5" cy="8.5" r="1"></circle>': "tag",
    '<rect x="7" y="2" width="10" height="20" rx="2"></rect><path d="M11 18h2"></path>': "device",
    '<circle cx="12" cy="12" r="9"></circle><circle cx="12" cy="12" r="3.5"></circle><path d="m5.6 5.6 3.9 3.9M14.5 14.5l3.9 3.9M18.4 5.6l-3.9 3.9M9.5 14.5l-3.9 3.9"></path>': "lifebuoy",
    '<path d="M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3ZM4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"></path>': "storage",
    '<circle cx="12" cy="12" r="9"></circle><path d="M12 11v6M12 7.5v.5"></path>': "info",
}

svg_re = re.compile(r"<svg\b[^>]*>(.*?)</svg>", re.S)
el_re = re.compile(r"<(path|circle|rect)\b([^>]*)>")
attr_re = re.compile(r'([\w:-]+)="([^"]*)"')


def num(value: str) -> str:
    f = float(value)
    return str(int(f)) if f == int(f) else repr(f)


def shapes(inner: str):
    for tag, raw in el_re.findall(inner):
        a = dict(attr_re.findall(raw))
        if tag == "path":
            yield "IconPath('%s')" % a["d"]
        elif tag == "circle":
            filled = ", filled: true" if a.get("fill") == "currentColor" else ""
            yield "IconCircle(%s, %s, %s%s)" % (num(a["cx"]), num(a["cy"]), num(a["r"]), filled)
        else:
            rx = ", rx: %s" % num(a["rx"]) if "rx" in a else ""
            yield "IconRect(%s, %s, %s, %s%s)" % (
                num(a["x"]), num(a["y"]), num(a["width"]), num(a["height"]), rx)


found = {}
for f in sorted(SRC.glob("*.html")):
    for inner in svg_re.findall(f.read_text(encoding="utf-8")):
        inner = re.sub(r"\s+", " ", inner.strip())
        if inner not in NAMES:
            sys.exit("Unnamed icon in %s:\n%s\nAdd it to NAMES in tool/gen_icons.py." % (f.name, inner))
        found[NAMES[inner]] = inner

lines = [
    "// GENERATED by tool/gen_icons.py from design/reference-html. Do not edit.",
    "",
    "import 'app_icon.dart';",
    "",
    "/// Every icon in the design kit, on a 24 unit grid.",
    "abstract final class AppIcons {",
]
for name in sorted(found):
    lines.append("  static const %s = AppIconData([" % name)
    for s in shapes(found[name]):
        lines.append("    %s," % s)
    lines.append("  ]);")
    lines.append("")
lines[-1] = "}"
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
print("wrote %d icons to %s" % (len(found), OUT.relative_to(ROOT)))

# Leave the file as `dart format` would, so a rerun changes nothing.
dart = shutil.which("dart") or shutil.which("dart", path=r"C:\src\flutter\bin")
if dart:
    subprocess.run([dart, "format", str(OUT)], check=True, stdout=subprocess.DEVNULL)
else:
    print("dart is not on PATH; run `dart format` on the file before committing")
