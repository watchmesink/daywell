#!/usr/bin/env python3
"""Compose App Store screenshots from the captures made by make-store-captures.sh.

Each slide places a headline and subheadline above a framed capture on a sunset
gradient matching the capture's appearance. Requires Pillow and the macOS system
font. Writes PNGs without alpha for the 6.3" (1206 × 2622) and 6.9" (1320 × 2868)
slots plus a contact sheet.
"""
import sys
from functools import cache
from pathlib import Path
from typing import NamedTuple

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / 'build/store-captures'
OUT = ROOT / 'publishing/screenshots'
FONT = '/System/Library/Fonts/SFNS.ttf'

SOURCE_SIZE = (1206, 2622)
SIZES = {'6.3-inch': (1206, 2622), '6.9-inch': (1320, 2868)}

# Layout of a 6.3" slide. Wider slots scale by canvas width / SOURCE_SIZE[0].
MARGIN = 92
COPY_TOP = 140
HEADLINE_SIZE = 110
HEADLINE_LEADING = 118
HEADLINE_GAP = 30
SUBHEAD_SIZE = 46
SUBHEAD_LEADING = 60
PHONE_TOP = 700
PHONE_INSET = 83
BEZEL_WIDTH = 26
SCREEN_RADIUS = 186
SHADOW_DROP = 28
SHADOW_ALPHA = 120
SHADOW_BLUR = 44
GLOW_RADIUS = 0.62
GLOW_HEIGHT = 0.12
GLOW_ALPHA = 150
GLOW_BLUR = 0.18

THUMBNAIL = (402, 874)
CONTACT_GAP = 24
FRAME_COLOR = (22, 22, 26)

THEMES = {
    'light': {'ink': (14, 10, 28), 'soft': (84, 76, 100), 'top': (252, 233, 216),
              'bottom': (204, 206, 221), 'sun': (255, 222, 168), 'shadow': (40, 30, 60)},
    'dark': {'ink': (255, 255, 255), 'soft': (206, 196, 214), 'top': (30, 21, 46),
             'bottom': (11, 8, 23), 'sun': (96, 52, 70), 'shadow': (0, 0, 0)},
}


class Slide(NamedTuple):
    slug: str
    capture: str
    headline: str
    subheadline: str


class Phone(NamedTuple):
    unit: float
    bezel: int
    width: int
    height: int
    screen_width: int
    screen_height: int
    x: int
    top: int
    radius: int


# A capture ending in -dark or -light sets the slide's theme. A newline in a
# headline forces the break; otherwise lines are balanced.
SLIDES = [
    Slide('01-choose-apps', 'apps-light.png',
          'Choose the apps.\nThat\u2019s it.',
          'Pick apps, whole categories, or websites in Apple\u2019s private Screen Time picker.'),
    Slide('02-no-account', 'dashboard-dark.png',
          'No account.\nNo sign-in.',
          'Nothing to sign up for. No server, no analytics. Nothing leaves your iPhone.'),
    Slide('03-shared-allowance', 'allowance-light.png',
          'One allowance,\nshared.',
          'Minutes add up across everything you pick. Then it\u2019s all blocked until tomorrow.'),
    Slide('04-simple', 'dashboard-light.png',
          'Simple\nby design.',
          'One screen shows what\u2019s blocked, when, and today\u2019s usage.'),
    Slide('05-private', 'apps-dark.png',
          'Private\nby default.',
          'Daywell never sees which apps you chose. Your rules stay on your iPhone.'),
    Slide('06-your-routine', 'allowance-dark.png',
          'Your time.\nYour routine.',
          'Set daily blocks and a shared allowance that fit your day.'),
]


# Typography -----------------------------------------------------------------

def font(size, weight):
    """Load the system font at `size` and select the named variation.

    Some Pillow builds expect the variation name as bytes rather than str.
    """
    face = ImageFont.truetype(FONT, size)
    try:
        face.set_variation_by_name(weight)
    except (OSError, ValueError):
        face.set_variation_by_name(weight.encode())
    return face


def wrap(text, face, width):
    """Fit `text` on the fewest lines, then even out a two-line break.

    A newline is a forced break; each piece is wrapped on its own. A word wider
    than `width` stays intact.
    """
    if '\n' in text:
        return [line for part in text.split('\n') for line in wrap(part, face, width)]
    words = text.split()
    lines, line = [], ''
    for word in words:
        trial = f'{line} {word}'.strip()
        if face.getlength(trial) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    if len(lines) != 2:
        return lines
    best, best_width = lines, max(face.getlength(item) for item in lines)
    for split in range(1, len(words)):
        left, right = ' '.join(words[:split]), ' '.join(words[split:])
        widest = max(face.getlength(left), face.getlength(right))
        if widest <= width and widest < best_width:
            best, best_width = [left, right], widest
    return best


def fitted(text, size, weight, width):
    """Shrink a headline until each forced line fits on one line.

    Gives up once the size drops below 40, even if a line still overflows.
    """
    while True:
        face = font(size, weight)
        lines = wrap(text, face, width)
        if '\n' not in text or len(lines) == text.count('\n') + 1 or size < 40:
            return face, lines
        size -= 2


# Backdrop and device --------------------------------------------------------

@cache
def _rounded_mask(size, radius, scale):
    big = Image.new('L', (size[0] * scale, size[1] * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, big.width - 1, big.height - 1), radius * scale, fill=255)
    return big.resize(size, Image.Resampling.LANCZOS)


def rounded_mask(size, radius, scale=4):
    """Antialiased rounded-rectangle mask, drawn `scale` times larger.

    Every slide of one canvas size uses the same frame and screen masks, so the
    supersampled draw is cached. Each call gets its own image.
    """
    return _rounded_mask(tuple(size), radius, scale).copy()


@cache
def _background(size, top, bottom, sun):
    width, height = size
    column = Image.new('RGB', (1, height))
    for y in range(height):
        blend = y / (height - 1)
        color = tuple(round(start + (end - start) * blend) for start, end in zip(top, bottom))
        column.putpixel((0, y), color)
    canvas = column.resize(size)
    glow = Image.new('L', size, 0)
    radius = int(width * GLOW_RADIUS)
    center_y = int(height * GLOW_HEIGHT)
    ImageDraw.Draw(glow).ellipse(
        (width // 2 - radius, center_y - radius, width // 2 + radius, center_y + radius),
        fill=GLOW_ALPHA)
    glow = glow.filter(ImageFilter.GaussianBlur(width * GLOW_BLUR))
    canvas.paste(Image.new('RGB', size, sun), mask=glow)
    return canvas


def background(size, theme):
    """Vertical theme gradient with a soft sun near the top.

    Slides that share a size and theme share one cached wash. The returned
    image is a copy, so later drawing does not change the next slide.
    """
    wash = _background(tuple(size), tuple(theme['top']), tuple(theme['bottom']), tuple(theme['sun']))
    return wash.copy()


def phone_geometry(size):
    """Frame and screen rectangles for a canvas of `size`, in pixels."""
    width = size[0]
    unit = width / SOURCE_SIZE[0]
    bezel = round(BEZEL_WIDTH * unit)
    phone_width = width - 2 * round(PHONE_INSET * unit)
    screen_width = phone_width - 2 * bezel
    scale = screen_width / SOURCE_SIZE[0]
    screen_height = round(SOURCE_SIZE[1] * scale)
    return Phone(
        unit=unit,
        bezel=bezel,
        width=phone_width,
        height=screen_height + 2 * bezel,
        screen_width=screen_width,
        screen_height=screen_height,
        x=(width - phone_width) // 2,
        top=round(PHONE_TOP * unit),
        radius=round(SCREEN_RADIUS * scale),
    )


def draw_copy(canvas, theme, headline, sub):
    width = canvas.size[0]
    unit = width / SOURCE_SIZE[0]
    margin = round(MARGIN * unit)
    text_width = width - 2 * margin
    draw = ImageDraw.Draw(canvas)
    y = round(COPY_TOP * unit)
    head, lines = fitted(headline, round(HEADLINE_SIZE * unit), 'Bold', text_width)
    for line in lines:
        draw.text((width / 2, y), line, font=head, fill=theme['ink'], anchor='ma')
        y += round(HEADLINE_LEADING * unit)
    y += round(HEADLINE_GAP * unit)
    body = font(round(SUBHEAD_SIZE * unit), 'Regular')
    for line in wrap(sub, body, text_width):
        draw.text((width / 2, y), line, font=body, fill=theme['soft'], anchor='ma')
        y += round(SUBHEAD_LEADING * unit)


def place_phone(canvas, capture, theme, phone):
    shadow = Image.new('L', canvas.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (phone.x, phone.top + round(SHADOW_DROP * phone.unit),
         phone.x + phone.width, phone.top + phone.height),
        phone.radius + phone.bezel, fill=SHADOW_ALPHA)
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR * phone.unit))
    canvas.paste(Image.new('RGB', canvas.size, theme['shadow']), mask=shadow)

    frame = Image.new('RGB', (phone.width, phone.height), FRAME_COLOR)
    canvas.paste(frame, (phone.x, phone.top),
                 rounded_mask((phone.width, phone.height), phone.radius + phone.bezel))
    screen = capture.resize((phone.screen_width, phone.screen_height), Image.Resampling.LANCZOS)
    canvas.paste(screen, (phone.x + phone.bezel, phone.top + phone.bezel),
                 rounded_mask((phone.screen_width, phone.screen_height), phone.radius))


def compose(size, capture, theme, headline, sub):
    """Stack the copy, a shadow, and a framed capture on the sunset background."""
    canvas = background(size, theme)
    draw_copy(canvas, theme, headline, sub)
    place_phone(canvas, capture, theme, phone_geometry(size))
    return canvas


# Rendering slides -----------------------------------------------------------

def theme_of(capture_name):
    """Theme for a capture whose stem ends in -light or -dark."""
    return THEMES[Path(capture_name).stem.rsplit('-', 1)[1]]


def clear_pngs(directory):
    for old in directory.glob('*.png'):
        old.unlink()


def save_slide(directory, size, slide):
    capture = Image.open(CAPTURES / slide.capture).convert('RGB')
    assert capture.size == SOURCE_SIZE, f'{slide.capture}: {capture.size}'
    image = compose(size, capture, theme_of(slide.capture), slide.headline, slide.subheadline)
    path = directory / f'{slide.slug}.png'
    image.save(path, optimize=True)
    return image, path


def write_contact_sheet(thumbnails):
    if not thumbnails:
        return
    gap = CONTACT_GAP
    thumb_width, thumb_height = THUMBNAIL
    sheet = Image.new(
        'RGB',
        (len(thumbnails) * (thumb_width + gap) + gap, thumb_height + 2 * gap),
        (255, 255, 255))
    for index, thumbnail in enumerate(thumbnails):
        sheet.paste(thumbnail, (gap + index * (thumb_width + gap), gap))
    path = OUT / 'contact-sheet.png'
    sheet.save(path, optimize=True)
    print(path, sheet.size)


def main():
    """Write every size, or only the slides named as command-line arguments.

    With no arguments, existing PNGs in each size folder are removed first.
    The contact sheet is rebuilt from the 6.3" slides that were written.
    """
    only = sys.argv[1:]
    thumbnails = []
    for folder, size in SIZES.items():
        directory = OUT / folder
        if not only:
            clear_pngs(directory)
        directory.mkdir(parents=True, exist_ok=True)
        for slide in SLIDES:
            if only and slide.slug not in only:
                continue
            image, path = save_slide(directory, size, slide)
            if folder == '6.3-inch':
                thumbnails.append(image.resize(THUMBNAIL, Image.Resampling.LANCZOS))
            print(path, image.size)
    write_contact_sheet(thumbnails)


if __name__ == '__main__':
    main()
