#!/usr/bin/env python3
"""Render sunset icon artwork and use the dark crop for Home Screen icons.

Requires Pillow. Artwork: ascii.rest, MIT; see Shared/AsciiRest-LICENSE.txt.
"""

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
# Approved square crop of the sunset artwork (left, upper, right, lower).
CROP = (560, 90, 1060, 590)
ICON_SIZE = (1024, 1024)
ICON_FILENAME = 'DaywellIcon.png'
INFO = {'author': 'xcode', 'version': 1}


def artwork_path(root, name):
    imageset = root / 'Shared' / 'Artwork.xcassets' / f'{name}.imageset'
    return imageset / f'{name}.png'


def app_iconset(root):
    return root / 'App' / 'Assets.xcassets' / 'AppIcon.appiconset'


def shield_imageset(root):
    return root / 'Shared' / 'ShieldArtwork.xcassets' / 'DaywellIcon.imageset'


def render(name, root=ROOT):
    """Return a 1024×1024 RGB icon cropped from the named sunset artwork."""
    with Image.open(artwork_path(root, name)) as opened:
        source = opened.convert('RGB')
    # Same composition for both appearances; leave the Home Screen mask to iOS.
    return source.crop(CROP).resize(ICON_SIZE, Image.Resampling.LANCZOS)


def same_pixels(existing, image):
    if existing.size != image.size:
        return False
    return existing.convert('RGB').tobytes() == image.tobytes()


def save_if_changed(image, path):
    """Save `image` as a PNG unless `path` already has the same pixels.

    Identical pixels keep the existing file bytes, including compression.
    """
    if path.exists():
        with Image.open(path) as existing:
            if same_pixels(existing, image):
                return
    image.save(path)


def app_icon_catalog():
    base = {'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}
    # Home Screen appearance is independent of the system's light/dark mode.
    # Use the requested dark fallback consistently, including older iOS releases.
    dark_appearance = [{'appearance': 'luminosity', 'value': 'dark'}]
    images = [
        dict(base, filename=ICON_FILENAME),
        dict(base, filename=ICON_FILENAME, appearances=dark_appearance),
    ]
    return {'images': images, 'info': INFO}


def shield_catalog():
    return {
        'images': [{'filename': ICON_FILENAME, 'idiom': 'universal'}],
        'info': INFO,
    }


def write_catalog(path, payload):
    path.write_text(json.dumps(payload, indent=2) + '\n')


def main(root=ROOT):
    """Write the dark sunset crop into the app icon and shield catalogs."""
    app = app_iconset(root)
    shield = shield_imageset(root)
    app.mkdir(parents=True, exist_ok=True)
    shield.mkdir(parents=True, exist_ok=True)

    dark = render('OceanSunset', root)
    save_if_changed(dark, app / ICON_FILENAME)
    save_if_changed(dark, shield / ICON_FILENAME)

    write_catalog(app / 'Contents.json', app_icon_catalog())
    write_catalog(shield / 'Contents.json', shield_catalog())
    for directory in (app.parent, shield.parent):
        write_catalog(directory / 'Contents.json', {'info': INFO})

    print(app / ICON_FILENAME)


if __name__ == '__main__':
    main()
