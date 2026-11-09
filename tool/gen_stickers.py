"""Draw the stickers the app comes with into app/assets/stickers/.

Every sticker is drawn here from circles, lines and the app's own font
(Figtree, under the SIL Open Font License), so the pack is original and
nobody else's art is shipped. Each is drawn four times too big and then
shrunk, which smooths its edges, and saved as a small PNG with a clear
background.

The names are what a sticker is sent as, so a name, once shipped, must
keep meaning the same picture. app/lib/data/stickers.dart lists them.

Run from the repository root:  python tool/gen_stickers.py
Needs Pillow:  python -m pip install Pillow
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "app" / "assets" / "stickers"
FONT = ROOT / "app" / "assets" / "fonts" / "Figtree-ExtraBold.ttf"

SIZE = 384  # What is saved.
GRID = 512  # What the drawings below are measured in.
SCALE = 4  # How much bigger they are drawn before shrinking.

INK = (36, 30, 46, 255)
WHITE = (255, 255, 255, 255)
CHEEK = (255, 128, 150, 150)
TEAR = (96, 178, 255, 255)


def s(value):
    """A length on the grid, in the pixels it is drawn at."""
    return int(round(value * SCALE * SIZE / GRID))


def box(cx, cy, rx, ry=None):
    ry = rx if ry is None else ry
    return [s(cx - rx), s(cy - ry), s(cx + rx), s(cy + ry)]


class Sticker:
    def __init__(self):
        self.image = Image.new("RGBA", (s(GRID), s(GRID)), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.image)

    def circle(self, cx, cy, r, fill, ry=None):
        self.draw.ellipse(box(cx, cy, r, ry), fill=fill)

    def ring(self, cx, cy, r, colour, width, ry=None):
        self.draw.ellipse(box(cx, cy, r, ry), outline=colour, width=s(width))

    def arc(self, cx, cy, r, start, end, colour, width, ry=None):
        self.draw.arc(box(cx, cy, r, ry), start, end, fill=colour, width=s(width))
        # Round ends, as a pen would leave.
        for angle in (start, end):
            x = cx + r * math.cos(math.radians(angle))
            y = cy + (ry or r) * math.sin(math.radians(angle))
            self.circle(x, y, width / 2, colour)

    def line(self, points, colour, width):
        scaled = [(s(x), s(y)) for x, y in points]
        self.draw.line(scaled, fill=colour, width=s(width), joint="curve")
        for x, y in points:
            self.circle(x, y, width / 2, colour)

    def polygon(self, points, fill):
        self.draw.polygon([(s(x), s(y)) for x, y in points], fill=fill)

    def chord(self, cx, cy, r, start, end, fill, ry=None):
        self.draw.chord(box(cx, cy, r, ry), start, end, fill=fill)

    def heart(self, cx, cy, size, fill):
        r = size * 0.3
        self.circle(cx - r, cy - r * 0.4, r, fill)
        self.circle(cx + r, cy - r * 0.4, r, fill)
        self.polygon(
            [
                (cx - size * 0.58, cy - r * 0.1),
                (cx + size * 0.58, cy - r * 0.1),
                (cx, cy + size * 0.62),
            ],
            fill,
        )

    def text(self, cx, cy, words, size, fill, outline=WHITE):
        font = ImageFont.truetype(str(FONT), s(size))
        self.draw.text(
            (s(cx), s(cy)),
            words,
            font=font,
            fill=fill,
            anchor="mm",
            stroke_width=s(size * 0.16),
            stroke_fill=outline,
        )

    def eyes(self, cx, cy, gap=46, r=15, ry=21):
        self.circle(cx - gap, cy, r, INK, ry)
        self.circle(cx + gap, cy, r, INK, ry)
        # A glint in each.
        self.circle(cx - gap + r * 0.35, cy - ry * 0.4, r * 0.32, WHITE)
        self.circle(cx + gap + r * 0.35, cy - ry * 0.4, r * 0.32, WHITE)

    def cheeks(self, cx, cy, gap=92):
        self.circle(cx - gap, cy, 20, CHEEK, 13)
        self.circle(cx + gap, cy, 20, CHEEK, 13)

    def save(self, name):
        drawn = self.image
        # A white edge all round, as a sticker cut from paper has, and a
        # soft shadow under it.
        alpha = drawn.getchannel("A")
        edge = alpha.filter(ImageFilter.MaxFilter(s(14) | 1))
        edge = edge.filter(ImageFilter.GaussianBlur(s(1.5)))
        shadow = edge.filter(ImageFilter.GaussianBlur(s(6)))
        out = Image.new("RGBA", drawn.size, (0, 0, 0, 0))
        out.paste((20, 16, 30, 70), (0, s(6)), shadow)
        out.paste(WHITE, (0, 0), edge)
        out.alpha_composite(drawn)
        out = out.resize((SIZE, SIZE), Image.LANCZOS)
        # Fewer colours keep the file small; the edges stay smooth.
        out = out.quantize(colors=128, method=Image.FASTOCTREE, dither=Image.NONE)
        OUT.mkdir(parents=True, exist_ok=True)
        out.save(OUT / f"{name}.png", optimize=True)


def blob(colour, cx=256, cy=270, r=170, ry=158):
    sticker = Sticker()
    sticker.circle(cx, cy, r, colour, ry)
    # A lighter patch where light falls on it.
    lighter = tuple(min(255, c + 36) for c in colour[:3]) + (255,)
    sticker.circle(cx - 70, cy - 84, 44, lighter, 24)
    return sticker


YELLOW = (255, 204, 64, 255)
PINK = (255, 132, 170, 255)
RED = (244, 84, 84, 255)
BLUE = (110, 168, 255, 255)
PURPLE = (170, 128, 255, 255)
ORANGE = (255, 156, 72, 255)
LAVENDER = (190, 176, 240, 255)
GREEN = (52, 199, 120, 255)


def hello():
    st = blob(YELLOW, cx=236, cy=290, r=160, ry=150)
    # The waving arm, and the lines that say it is moving.
    st.line([(340, 250), (412, 168)], YELLOW, 46)
    st.circle(416, 160, 36, YELLOW)
    for angle in (-75, -40, -5):
        a = math.radians(angle)
        x, y = 416 + 62 * math.cos(a), 160 + 62 * math.sin(a)
        st.line([(x, y), (x + 18 * math.cos(a), y + 18 * math.sin(a))], INK, 9)
    st.eyes(236, 262)
    st.cheeks(236, 318, 88)
    st.arc(236, 318, 46, 20, 160, INK, 12)
    st.text(140, 96, "Hi!", 96, INK)
    st.save("hello")


def thanks():
    st = blob(PINK)
    st.arc(210, 250, 22, 200, 340, INK, 11)
    st.arc(302, 250, 22, 200, 340, INK, 11)
    st.cheeks(256, 300)
    st.arc(256, 300, 34, 20, 160, INK, 11)
    st.heart(256, 392, 120, RED)
    st.text(256, 74, "Thanks!", 82, INK)
    st.save("thanks")


def lol():
    st = blob(YELLOW)
    # Eyes shut tight with laughing.
    st.line([(170, 220), (205, 240), (170, 260)], INK, 12)
    st.line([(342, 220), (307, 240), (342, 260)], INK, 12)
    st.chord(256, 300, 92, 0, 180, INK, 80)
    st.chord(256, 330, 50, 0, 180, (255, 110, 120, 255), 36)
    # Tears flying off.
    st.circle(118, 262, 20, TEAR, 30)
    st.circle(394, 262, 20, TEAR, 30)
    st.text(256, 470, "LOL", 92, INK)
    st.save("lol")


def love():
    st = blob(PINK)
    st.heart(200, 248, 70, RED)
    st.heart(312, 248, 70, RED)
    st.arc(256, 310, 44, 20, 160, INK, 12)
    st.heart(96, 96, 56, RED)
    st.heart(410, 70, 40, RED)
    st.heart(440, 160, 30, RED)
    st.save("love")


def wow():
    st = blob(PURPLE)
    st.circle(204, 236, 30, WHITE)
    st.circle(308, 236, 30, WHITE)
    st.circle(204, 240, 15, INK)
    st.circle(308, 240, 15, INK)
    st.circle(256, 340, 34, INK, 42)
    st.line([(186, 186), (226, 176)], INK, 9)
    st.line([(286, 176), (326, 186)], INK, 9)
    st.text(256, 70, "WOW", 104, INK)
    st.save("wow")


def sad():
    st = blob(BLUE)
    st.eyes(256, 248, 50, 13, 18)
    st.line([(180, 206), (218, 196)], INK, 9)
    st.line([(294, 196), (332, 206)], INK, 9)
    st.arc(256, 356, 40, 200, 340, INK, 12)
    st.circle(196, 300, 19, WHITE, 26)
    st.polygon([(178, 294), (214, 294), (196, 256)], WHITE)
    st.circle(196, 300, 13, (200, 236, 255, 255), 19)
    st.polygon([(185, 296), (207, 296), (196, 270)], (200, 236, 255, 255))
    st.save("sad")


def angry():
    st = blob(RED)
    st.line([(170, 200), (226, 228)], INK, 13)
    st.line([(342, 200), (286, 228)], INK, 13)
    st.circle(204, 252, 14, INK, 16)
    st.circle(308, 252, 14, INK, 16)
    st.arc(256, 356, 42, 205, 335, INK, 13)
    # Steam.
    for cx in (110, 402):
        st.circle(cx, 120, 30, (230, 230, 240, 255))
        st.circle(cx + (22 if cx < 256 else -22), 92, 24, (230, 230, 240, 255))
    st.save("angry")


def cool():
    st = blob(ORANGE)
    # Sunglasses.
    st.chord(196, 236, 56, 0, 180, INK, 46)
    st.chord(316, 236, 56, 0, 180, INK, 46)
    st.line([(130, 238), (382, 238)], INK, 14)
    st.line([(170, 248), (190, 264)], (255, 255, 255, 120), 6)
    st.line([(290, 248), (310, 264)], (255, 255, 255, 120), 6)
    st.arc(270, 318, 46, 20, 120, INK, 12)
    st.text(256, 470, "cool", 84, INK)
    st.save("cool")


def sleepy():
    st = blob(LAVENDER)
    st.arc(204, 252, 26, 20, 160, INK, 11)
    st.arc(308, 252, 26, 20, 160, INK, 11)
    st.circle(256, 336, 16, INK, 12)
    st.text(380, 120, "z", 64, INK)
    st.text(424, 72, "z", 52, INK)
    st.text(330, 160, "Z", 80, INK)
    st.save("sleepy")


def party():
    st = blob(YELLOW, cy=300, r=160, ry=148)
    # A hat, and its pompom.
    st.polygon([(196, 168), (316, 168), (268, 30)], (120, 110, 255, 255))
    st.line([(222, 120), (296, 132)], (255, 220, 90, 255), 12)
    st.circle(268, 30, 22, (255, 98, 140, 255))
    st.eyes(256, 276)
    st.chord(256, 318, 60, 0, 180, INK, 54)
    for x, y, c in [
        (70, 110, (255, 98, 140, 255)),
        (440, 120, (90, 200, 255, 255)),
        (90, 420, (52, 199, 120, 255)),
        (430, 400, (255, 156, 72, 255)),
        (60, 260, (120, 110, 255, 255)),
        (460, 260, (255, 204, 64, 255)),
    ]:
        st.polygon([(x - 14, y - 6), (x + 10, y - 16), (x + 14, y + 6), (x - 10, y + 16)], c)
    st.save("party")


def ok():
    st = Sticker()
    st.circle(256, 230, 170, GREEN)
    st.circle(214, 166, 40, (110, 225, 160, 255), 24)
    st.line([(170, 236), (232, 296), (346, 172)], WHITE, 40)
    st.text(256, 450, "OK!", 104, INK)
    st.save("ok")


def cat():
    st = Sticker()
    fur = (255, 168, 76, 255)
    st.polygon([(110, 210), (150, 60), (240, 140)], fur)
    st.polygon([(402, 210), (362, 60), (272, 140)], fur)
    st.polygon([(140, 176), (158, 104), (204, 146)], (255, 196, 200, 255))
    st.polygon([(372, 176), (354, 104), (308, 146)], (255, 196, 200, 255))
    st.circle(256, 290, 170, fur, 150)
    st.eyes(256, 270, 62, 15, 22)
    st.polygon([(240, 316), (272, 316), (256, 334)], (255, 110, 140, 255))
    st.arc(240, 342, 16, 20, 150, INK, 8)
    st.arc(272, 342, 16, 30, 160, INK, 8)
    for side in (-1, 1):
        for dy in (-12, 12):
            st.line([(256 + side * 100, 320 + dy), (256 + side * 176, 310 + dy * 2)], INK, 6)
    st.save("cat")


if __name__ == "__main__":
    for draw in (hello, thanks, lol, love, wow, sad, angry, cool, sleepy, party, ok, cat):
        draw()
    for path in sorted(OUT.glob("*.png")):
        print(f"{path.name}: {path.stat().st_size} bytes")
