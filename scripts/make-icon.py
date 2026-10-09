#!/usr/bin/env python3
"""Render the approved sunset crop for the app and blocking screen.

Requires Pillow. Artwork: ascii.rest, MIT; see Shared/AsciiRest-LICENSE.txt.
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / 'Shared/Artwork.xcassets/OceanSunset.imageset/OceanSunset.png').convert('RGB')
# Exact crop approved in the preview. Leave the Home Screen mask to iOS.
icon = source.crop((560, 90, 1060, 590)).resize((1024, 1024), Image.Resampling.LANCZOS)
info = {'author': 'xcode', 'version': 1}
app = ROOT / 'App/Assets.xcassets/AppIcon.appiconset'
shield = ROOT / 'Shared/ShieldArtwork.xcassets/DaywellIcon.imageset'
for directory in (app, shield):
    directory.mkdir(parents=True, exist_ok=True)
    icon.save(directory / 'DaywellIcon.png')
    entry = {'filename': 'DaywellIcon.png', 'idiom': 'universal'}
    if directory == app:
        entry.update(platform='ios', size='1024x1024')
    (directory / 'Contents.json').write_text(json.dumps({'images': [entry], 'info': info}, indent=2) + '\n')
    (directory.parent / 'Contents.json').write_text(json.dumps({'info': info}, indent=2) + '\n')
(app / 'AppIcon.png').unlink(missing_ok=True)
print(app / 'DaywellIcon.png')
