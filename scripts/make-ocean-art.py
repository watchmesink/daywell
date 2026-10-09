#!/usr/bin/env python3
"""Create bundled static artwork from ascii.rest's MIT-licensed ocean sunset.

Development requirements: Node 22.13+ and Pillow. No runtime dependencies.
Source: https://github.com/bas3line/ascii/blob/main/src/pieces/ocean-sunset.ts
License: Shared/AsciiRest-LICENSE.txt
"""
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
frame = json.loads(subprocess.check_output(['node', str(ROOT / 'scripts/render-ocean-frame.mjs')]))
meta = frame['meta']
cell, supersampling = 6, 3
image = Image.new('RGB', (meta['cols'] * cell * supersampling, meta['rows'] * cell * supersampling), meta['ground'])
draw = ImageDraw.Draw(image)
radii = {' ': 0, '·': 0.12, '•': 0.27, '●': 0.44}
for row, line in enumerate(frame['frame'].splitlines()):
    for col, glyph in enumerate(line):
        radius = radii[glyph] * cell * supersampling
        if not radius:
            continue
        x, y = (col + 0.5) * cell * supersampling, (row + 0.5) * cell * supersampling
        draw.ellipse((x - radius, y - radius, x + radius, y + radius),
                     fill=meta['palette'][frame['colors'][row * meta['cols'] + col]])
image = image.resize((meta['cols'] * cell, meta['rows'] * cell), Image.Resampling.LANCZOS)
catalog = ROOT / 'Shared/Artwork.xcassets'
asset = catalog / 'OceanSunset.imageset'
asset.mkdir(parents=True, exist_ok=True)
image.save(asset / 'OceanSunset.png', optimize=True)
info = {'author': 'xcode', 'version': 1}
(catalog / 'Contents.json').write_text(json.dumps({'info': info}, indent=2) + '\n')
(asset / 'Contents.json').write_text(json.dumps({
    'images': [{'filename': 'OceanSunset.png', 'idiom': 'universal'}], 'info': info
}, indent=2) + '\n')
print(asset / 'OceanSunset.png')
