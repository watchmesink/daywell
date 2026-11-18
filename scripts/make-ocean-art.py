#!/usr/bin/env python3
"""Create bundled static artwork from ascii.rest's MIT-licensed ocean sunset.

Development requirements: Node 22.13+ and Pillow. No runtime dependencies.
Source: https://github.com/bas3line/ascii/blob/main/src/pieces/ocean-sunset.ts
License: Shared/AsciiRest-LICENSE.txt
"""
import json
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RENDERER = ROOT / 'scripts/render-ocean-frame.mjs'
CATALOG = ROOT / 'Shared/Artwork.xcassets'
IMAGESET_NAME = 'OceanSunset'

# Draw each cell at this many pixels, then downsample for smoother dots.
CELL = 6
SUPERSAMPLING = 3
# Radius as a fraction of one cell. A space leaves the ground color as-is.
GLYPH_RADII = {
    ' ': 0,
    '·': 0.12,
    '•': 0.27,
    '●': 0.44,
}
ASSET_INFO = {'author': 'xcode', 'version': 1}


def load_frame(renderer=None):
    """Return the ocean frame JSON produced by the Node renderer."""
    if renderer is None:
        renderer = RENDERER
    return json.loads(subprocess.check_output(['node', str(renderer)]))


def render_image(frame, cell=CELL, supersampling=SUPERSAMPLING):
    """Paint one palette-colored dot per glyph and downsample with Lanczos.

    Blank glyphs keep the ground color and do not read a palette index.
    """
    meta = frame['meta']
    columns = meta['cols']
    sampled_cell = cell * supersampling
    image = Image.new(
        'RGB',
        (columns * sampled_cell, meta['rows'] * sampled_cell),
        meta['ground'],
    )
    draw = ImageDraw.Draw(image)
    palette = meta['palette']
    colors = frame['colors']

    for row, line in enumerate(frame['frame'].splitlines()):
        for col, glyph in enumerate(line):
            radius = GLYPH_RADII[glyph] * cell * supersampling
            if not radius:
                continue
            x = (col + 0.5) * cell * supersampling
            y = (row + 0.5) * cell * supersampling
            color = palette[colors[row * columns + col]]
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)

    output_size = (columns * cell, meta['rows'] * cell)
    return image.resize(output_size, Image.Resampling.LANCZOS)


def write_catalog(image, catalog=None, name=IMAGESET_NAME):
    """Write the PNG plus Xcode asset-catalog metadata. Return the PNG path."""
    if catalog is None:
        catalog = CATALOG
    asset = catalog / f'{name}.imageset'
    asset.mkdir(parents=True, exist_ok=True)
    image_path = asset / f'{name}.png'
    image.save(image_path, optimize=True)
    (catalog / 'Contents.json').write_text(json.dumps({'info': ASSET_INFO}, indent=2) + '\n')
    (asset / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': f'{name}.png', 'idiom': 'universal'}],
        'info': ASSET_INFO,
    }, indent=2) + '\n')
    return image_path


def main():
    print(write_catalog(render_image(load_frame())))


if __name__ == '__main__':
    main()
