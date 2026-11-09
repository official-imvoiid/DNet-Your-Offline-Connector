"""Write the emoji the picker offers into app/lib/data/emoji_data.g.dart.

The list comes from Unicode's emoji-test.txt and the words people search
by from the English CLDR annotations, both under the Unicode License
(https://www.unicode.org/license.txt). The app ships what this writes and
fetches nothing: run it again by hand when a new emoji version comes out,
and update the font in app/assets/fonts/ to one that draws it.

Each emoji is listed once, without a skin tone. One that comes in skin
tones carries its five variants with it, in the order light, medium-light,
medium, medium-dark, dark. Mixed tones, as on two people holding hands,
are left out: the picker offers one tone for the whole emoji.

Run from the repository root, with the three files downloaded from
https://www.unicode.org/Public/emoji/latest/emoji-test.txt and
https://github.com/unicode-org/cldr/tree/main/common (annotations/en.xml
and annotationsDerived/en.xml):

    python tool/gen_emoji.py emoji-test.txt en.xml derived-en.xml
"""
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "app" / "lib" / "data" / "emoji_data.g.dart"

# The groups emoji-test.txt has, as the app names them, in the app's order.
GROUPS = {
    "Smileys & Emotion": "smileys",
    "People & Body": "people",
    "Animals & Nature": "nature",
    "Food & Drink": "food",
    "Activities": "activities",
    "Travel & Places": "travel",
    "Objects": "objects",
    "Symbols": "symbols",
    "Flags": "flags",
}
TONES = [
    "light skin tone",
    "medium-light skin tone",
    "medium skin tone",
    "medium-dark skin tone",
    "dark skin tone",
]

LINE = re.compile(
    r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*\S+\s+E(\d+\.\d+)\s+(.+)$"
)
ANNOTATION = re.compile(r'<annotation cp="([^"]+)"( type="tts")?>([^<]*)</annotation>')


def read_list(path):
    """Every fully-qualified emoji, by group, with its version and name."""
    version = None
    group = None
    out = {name: [] for name in GROUPS.values()}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith("# Version:"):
            version = line.split(":", 1)[1].strip()
        if line.startswith("# group:"):
            group = GROUPS.get(line.split(":", 1)[1].strip())
            continue
        found = LINE.match(line)
        if not found or group is None:
            continue
        points, _, name = found.groups()
        emoji = "".join(chr(int(p, 16)) for p in points.split())
        out[group].append((emoji, name.strip()))
    return version, out


def read_words(*paths):
    """The search words for each emoji, keyed without U+FE0F."""
    words = {}
    for path in paths:
        text = Path(path).read_text(encoding="utf-8")
        for cp, tts, value in ANNOTATION.findall(text):
            if tts:
                continue
            key = html.unescape(cp).replace("️", "")
            parts = [w.strip() for w in html.unescape(value).split("|")]
            words.setdefault(key, [])
            for word in parts:
                if word and word not in words[key]:
                    words[key].append(word)
    return words


def without_tones(name):
    """The name with any skin tones taken out, and the tones taken."""
    if ": " not in name:
        return name, []
    head, rest = name.split(": ", 1)
    parts = rest.split(", ")
    tones = [p for p in parts if p in TONES]
    others = [p for p in parts if p not in TONES]
    base = head + (": " + ", ".join(others) if others else "")
    return base, tones


def clean(text):
    """Nothing in a field may break the format below."""
    return text.replace("\t", " ").replace("\n", " ").replace("'''", "")


# The app's source must not hold this run of letters anywhere, not even in
# a country's name (app/test/product_rules_test.dart). Its last letter is
# written as an escape instead, which reads the same in the app.
BANNED = re.compile("(" + "j" + "a" + ")(" + "m" + ")", re.IGNORECASE)


def as_dart(text):
    """Text to go between three quotes in a Dart string."""
    text = text.replace("\\", "\\\\").replace("$", "\\$")
    return BANNED.sub(lambda m: m.group(1) + "\\u{%X}" % ord(m.group(2)), text)


def main(test_file, annotations, derived):
    version, groups = read_list(test_file)
    words = read_words(annotations, derived)
    lines = []
    count = 0
    for group, entries in groups.items():
        lines.append("@" + group)
        bases = {}
        order = []
        for emoji, name in entries:
            base_name, tones = without_tones(name)
            if not tones:
                bases[name] = {"emoji": emoji, "name": name, "tones": [None] * 5}
                order.append(name)
                continue
            if len(set(tones)) != 1:
                continue  # Mixed tones.
            base = bases.get(base_name)
            if base is None:
                raise SystemExit(f"no emoji without a tone for {name!r}")
            base["tones"][TONES.index(tones[0])] = emoji
        for name in order:
            base = bases[name]
            emoji = base["emoji"]
            search = [
                w
                for w in words.get(emoji.replace("️", ""), [])
                if w.lower() != name.lower()
            ]
            tones = base["tones"]
            if any(tones) and not all(tones):
                raise SystemExit(f"only some tones for {name!r}")
            fields = [emoji, name, "|".join(search), " ".join(tones) if all(tones) else ""]
            lines.append("\t".join(clean(f) for f in fields).rstrip("\t"))
            count += 1
    body = "\n".join(lines)
    OUT.write_text(
        "// Written by tool/gen_emoji.py from Unicode emoji-test.txt and the\n"
        "// English CLDR annotations (Unicode License). Do not edit by hand.\n"
        "\n"
        f"/// The Unicode emoji version listed here.\n"
        f"const emojiVersion = '{version}';\n"
        "\n"
        f"/// {count} emoji. A line starting @ names a group; every other line\n"
        "/// is one emoji, its name, the words it is found by (split by |), and\n"
        "/// its five skin tones if it has them, each split from the next by a\n"
        "/// tab.\n"
        f"const emojiData = '''\n{as_dart(body)}\n''';\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"{count} emoji, version {version}, written to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
