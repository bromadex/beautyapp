"""Draws the BeauTap app icon (ink square, gold "B", cream dot) at every
size Android, the website and Google Play need.

    python3 tool/make_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / 'assets/fonts/Manrope-ExtraBold.ttf'
INK = (20, 18, 16, 255)
GOLD = (200, 161, 90, 255)
CREAM = (247, 243, 236, 255)
SCALE = 4  # draw big, then shrink, for smooth edges


def glyph(size, frac, bg=None, radius=0.0):
    """A size x size image with the "B." mark taking `frac` of the height."""
    s = size * SCALE
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if bg:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * radius), fill=bg)
    font = ImageFont.truetype(str(FONT), int(s * frac))
    box = d.textbbox((0, 0), 'B', font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    dot = h * 0.2
    gap = h * 0.04
    total = w + gap + dot
    x = (s - total) / 2 - box[0]
    y = (s - h) / 2 - box[1]
    d.text((x, y), 'B', font=font, fill=GOLD)
    dx = (s - total) / 2 + w + gap
    dy = (s + h) / 2 - dot
    d.ellipse([dx, dy, dx + dot, dy + dot], fill=CREAM)
    return img.resize((size, size), Image.LANCZOS)


def save(img, path):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(path.relative_to(ROOT), img.size)


# Website and installable web app
save(glyph(512, 0.56, INK), 'web/icons/Icon-512.png')
save(glyph(192, 0.56, INK), 'web/icons/Icon-192.png')
save(glyph(512, 0.42, INK), 'web/icons/Icon-maskable-512.png')   # inside the 80% safe zone
save(glyph(192, 0.42, INK), 'web/icons/Icon-maskable-192.png')
save(glyph(64, 0.6, INK, 0.22), 'web/favicon.png')

# Android: legacy icons, and adaptive-icon foregrounds (108dp canvas, mark kept
# inside the 66dp safe circle; the background colour is in values/colors.xml)
for name, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save(glyph(px, 0.56, INK, 0.22), f'android/app/src/main/res/mipmap-{name}/ic_launcher.png')
for name, px in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
    for folder in (f'drawable-{name}', f'drawable-night-{name}'):
        if (ROOT / 'android/app/src/main/res' / folder / 'ic_launcher_foreground.png').exists():
            save(glyph(px, 0.44), f'android/app/src/main/res/{folder}/ic_launcher_foreground.png')

# Google Play listing (Play rounds the corners itself)
save(glyph(512, 0.56, INK), 'store/icon-512.png')


def wordmark(w, h):
    """Gold "BeauTap" with the cream dot, for the launch screen on older Android."""
    s = SCALE
    img = Image.new('RGBA', (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(str(FONT), int(h * s * 0.42))
    box = d.textbbox((0, 0), 'BeauTap', font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    dot = th * 0.2
    gap = th * 0.05
    x = (w * s - (tw + gap + dot)) / 2 - box[0]
    y = (h * s - th) / 2 - box[1]
    d.text((x, y), 'BeauTap', font=font, fill=GOLD)
    base = d.textbbox((x, y), 'B', font=font)[3]  # baseline, ignoring the tail of the "p"
    dx = (w * s - (tw + gap + dot)) / 2 + tw + gap
    dy = base - dot
    d.ellipse([dx, dy, dx + dot, dy + dot], fill=CREAM)
    return img.resize((w, h), Image.LANCZOS)


# Launch screen: ink background, the mark in the middle
RES = 'android/app/src/main/res'
for folder in ('drawable', 'drawable-v21'):
    save(Image.new('RGBA', (1, 1), INK), f'{RES}/{folder}/background.png')
for name, mult in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
    save(wordmark(int(256 * mult), int(115 * mult)), f'{RES}/drawable-{name}/splash.png')
    for folder in (f'drawable-{name}', f'drawable-night-{name}'):
        save(glyph(int(256 * mult), 0.34), f'{RES}/{folder}/android12splash.png')


# In-app logo (sidebar) and the source icon referenced in pubspec.yaml
save(glyph(512, 0.56, INK), 'assets/branding/app_mark.png')
save(glyph(1024, 0.56, INK), 'assets/branding/app_icon.png')
save(glyph(1024, 0.44), 'assets/branding/app_icon_foreground.png')
