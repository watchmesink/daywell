#!/usr/bin/env python3
"""Render matching light/dark Home Screen icons and the original shield crop.

Requires Pillow. Artwork: ascii.rest, MIT; see Shared/AsciiRest-LICENSE.txt.
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CROP = (560, 90, 1060, 590)
INFO = {'author': 'xcode', 'version': 1}


def render(name):
    source = Image.open(ROOT / f'Shared/Artwork.xcassets/{name}.imageset/{name}.png').convert('RGB')
    # Same composition for both appearances; leave the Home Screen mask to iOS.
    return source.crop(CROP).resize((1024, 1024), Image.Resampling.LANCZOS)


def save_if_changed(image, path):
    # Preserve existing PNG bytes when regenerated pixels are identical.
    if path.exists():
        with Image.open(path) as existing:
            if existing.size == image.size and existing.convert('RGB').tobytes() == image.tobytes():
                return
    image.save(path)


app = ROOT / 'App/Assets.xcassets/AppIcon.appiconset'
shield = ROOT / 'Shared/ShieldArtwork.xcassets/DaywellIcon.imageset'
app.mkdir(parents=True, exist_ok=True)
shield.mkdir(parents=True, exist_ok=True)
dark = render('OceanSunset')
light = render('OceanSunsetLight')
save_if_changed(dark, app / 'DaywellIcon.png')
save_if_changed(light, app / 'DaywellIconLight.png')
save_if_changed(dark, shield / 'DaywellIcon.png')

base = {'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}
images = [
    dict(base, filename='DaywellIconLight.png'),
    dict(base, filename='DaywellIcon.png', appearances=[{'appearance': 'luminosity', 'value': 'dark'}])
]
(app / 'Contents.json').write_text(json.dumps({'images': images, 'info': INFO}, indent=2) + '\n')
(shield / 'Contents.json').write_text(json.dumps({
    'images': [{'filename': 'DaywellIcon.png', 'idiom': 'universal'}], 'info': INFO
}, indent=2) + '\n')
for directory in (app.parent, shield.parent):
    (directory / 'Contents.json').write_text(json.dumps({'info': INFO}, indent=2) + '\n')
print(app / 'DaywellIconLight.png')
print(app / 'DaywellIcon.png')
