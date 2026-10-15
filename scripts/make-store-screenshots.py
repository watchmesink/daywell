#!/usr/bin/env python3
"""Compose App Store screenshots from the captures made by make-store-captures.sh.

Each slide places a headline and subheadline above a framed capture on a sunset
gradient matching the capture's appearance. Requires Pillow and the macOS system
font. Writes PNGs without alpha for the 6.3" (1206 × 2622) and 6.9" (1320 × 2868)
slots plus a contact sheet.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / 'build/store-captures'
OUT = ROOT / 'publishing/screenshots'
FONT = '/System/Library/Fonts/SFNS.ttf'
SOURCE_SIZE = (1206, 2622)
SIZES = {'6.3-inch': (1206, 2622), '6.9-inch': (1320, 2868)}

THEMES = {
    'light': {'ink': (14, 10, 28), 'soft': (84, 76, 100), 'top': (252, 233, 216),
              'bottom': (204, 206, 221), 'sun': (255, 222, 168), 'shadow': (40, 30, 60)},
    'dark': {'ink': (255, 255, 255), 'soft': (206, 196, 214), 'top': (30, 21, 46),
             'bottom': (11, 8, 23), 'sun': (96, 52, 70), 'shadow': (0, 0, 0)},
}
BEZEL = (22, 22, 26)

# (slug, capture, headline, subheadline). A capture ending in -dark or -light sets
# the slide's theme. A newline in a headline forces the break; otherwise lines are balanced.
SLIDES = [
    ('01-choose-apps', 'apps-light.png',
     'Choose the apps.\nThat\u2019s it.',
     'Pick apps, whole categories, or websites in Apple\u2019s private Screen Time picker.'),
    ('02-no-account', 'dashboard-dark.png',
     'No account.\nNo sign-in.',
     'Nothing to sign up for. No server, no analytics. Nothing leaves your iPhone.'),
    ('03-shared-allowance', 'allowance-light.png',
     'One allowance,\nshared.',
     'Minutes add up across everything you pick. Then it\u2019s all blocked until tomorrow.'),
    ('04-simple', 'dashboard-light.png',
     'Simple\nby design.',
     'One screen shows what\u2019s blocked, when, and how much time is left.'),
    ('05-private', 'apps-dark.png',
     'Private\nby default.',
     'Daywell never sees which apps you chose. Your rules stay on your iPhone.'),
    ('06-your-routine', 'allowance-dark.png',
     'Your time.\nYour routine.',
     'Set daily blocks and a shared allowance that fit your day.'),
]


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(weight)
    except (OSError, ValueError):
        f.set_variation_by_name(weight.encode())
    return f


def wrap(text, f, width):
    # Fewest lines that fit, then the split that keeps those lines most even.
    if '\n' in text:
        return [line for part in text.split('\n') for line in wrap(part, f, width)]
    words = text.split()
    lines, line = [], ''
    for word in words:
        trial = f'{line} {word}'.strip()
        if f.getlength(trial) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    if len(lines) != 2:
        return lines
    best, best_width = lines, max(f.getlength(l) for l in lines)
    for i in range(1, len(words)):
        a, b = ' '.join(words[:i]), ' '.join(words[i:])
        w = max(f.getlength(a), f.getlength(b))
        if w <= width and w < best_width:
            best, best_width = [a, b], w
    return best


def fitted(text, size, weight, width):
    # Shrink until every forced line fits on one line.
    while True:
        f = font(size, weight)
        lines = wrap(text, f, width)
        if '\n' not in text or len(lines) == text.count('\n') + 1 or size < 40:
            return f, lines
        size -= 2


def rounded_mask(size, radius, scale=4):
    big = Image.new('L', (size[0] * scale, size[1] * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius * scale, fill=255)
    return big.resize(size, Image.Resampling.LANCZOS)


def background(size, theme):
    w, h = size
    top, bottom = theme['top'], theme['bottom']
    column = Image.new('RGB', (1, h))
    for y in range(h):
        t = y / (h - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    canvas = column.resize(size)
    glow = Image.new('L', size, 0)
    r = int(w * 0.62)
    ImageDraw.Draw(glow).ellipse((w // 2 - r, int(h * 0.12) - r, w // 2 + r, int(h * 0.12) + r), fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.18))
    canvas.paste(Image.new('RGB', size, theme['sun']), mask=glow)
    return canvas


def compose(size, capture, theme, headline, sub):
    w, h = size
    u = w / SOURCE_SIZE[0]
    canvas = background(size, theme)
    draw = ImageDraw.Draw(canvas)

    margin = round(92 * u)
    y = round(140 * u)
    head, lines = fitted(headline, round(110 * u), 'Bold', w - 2 * margin)
    for line in lines:
        draw.text((w / 2, y), line, font=head, fill=theme['ink'], anchor='ma')
        y += round(118 * u)
    y += round(30 * u)
    body = font(round(46 * u), 'Regular')
    for line in wrap(sub, body, w - 2 * margin):
        draw.text((w / 2, y), line, font=body, fill=theme['soft'], anchor='ma')
        y += round(60 * u)

    phone_top = round(700 * u)
    bezel = round(26 * u)
    phone_w = w - 2 * round(83 * u)
    screen_w = phone_w - 2 * bezel
    scale = screen_w / SOURCE_SIZE[0]
    screen_h = round(SOURCE_SIZE[1] * scale)
    phone_h = screen_h + 2 * bezel
    phone_x = (w - phone_w) // 2
    radius = round(186 * scale)

    shadow = Image.new('L', size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (phone_x, phone_top + round(28 * u), phone_x + phone_w, phone_top + phone_h), radius + bezel, fill=120)
    shadow = shadow.filter(ImageFilter.GaussianBlur(44 * u))
    canvas.paste(Image.new('RGB', size, theme['shadow']), mask=shadow)

    frame = Image.new('RGB', (phone_w, phone_h), BEZEL)
    canvas.paste(frame, (phone_x, phone_top), rounded_mask((phone_w, phone_h), radius + bezel))
    screen = capture.resize((screen_w, screen_h), Image.Resampling.LANCZOS)
    canvas.paste(screen, (phone_x + bezel, phone_top + bezel), rounded_mask((screen_w, screen_h), radius))
    return canvas


def main():
    only = sys.argv[1:]
    sheets = []
    for folder, size in SIZES.items():
        out = OUT / folder
        if not only:
            for old in out.glob('*.png'):
                old.unlink()
        out.mkdir(parents=True, exist_ok=True)
        for slug, name, headline, sub in SLIDES:
            if only and slug not in only:
                continue
            capture = Image.open(CAPTURES / name).convert('RGB')
            assert capture.size == SOURCE_SIZE, f'{name}: {capture.size}'
            theme = THEMES[Path(name).stem.rsplit('-', 1)[1]]
            image = compose(size, capture, theme, headline, sub)
            image.save(out / f'{slug}.png', optimize=True)
            if folder == '6.3-inch':
                sheets.append(image.resize((402, 874), Image.Resampling.LANCZOS))
            print(out / f'{slug}.png', image.size)
    if sheets:
        gap = 24
        sheet = Image.new('RGB', (len(sheets) * (402 + gap) + gap, 874 + 2 * gap), (255, 255, 255))
        for i, s in enumerate(sheets):
            sheet.paste(s, (gap + i * (402 + gap), gap))
        sheet.save(OUT / 'contact-sheet.png', optimize=True)
        print(OUT / 'contact-sheet.png', sheet.size)


if __name__ == '__main__':
    main()
