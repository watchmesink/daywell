#!/usr/bin/env python3
"""Behavior checks for scripts/make-ocean-art.py. Run: python3 scripts/test_make_ocean_art.py"""
import hashlib
import importlib.util
import io
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = Path(__file__).resolve().parent / 'make-ocean-art.py'
BUNDLED = ROOT / 'Shared/Artwork.xcassets'
GROUND = (0x0B, 0x08, 0x17)

FIXTURE = {
    'meta': {
        'cols': 3,
        'rows': 2,
        'ground': '#0b0817',
        'palette': ['#ff0000', '#00ff00', '#0000ff'],
    },
    'frame': '· •\n●● ',
    'colors': [0, 1, 2, 1, 0, 2],
}
# Pixel lock for FIXTURE at the script's cell size and supersampling.
FIXTURE_SHA256 = 'fa7686f3af326e3006024f001ae05e9f23b784f4375cc865935fb9705c4efc0d'


def load_script():
    spec = importlib.util.spec_from_file_location('make_ocean_art', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


art = load_script()


class OceanArtScriptTests(unittest.TestCase):
    def test_importing_the_script_does_not_generate_artwork(self):
        png = BUNDLED / 'OceanSunset.imageset' / 'OceanSunset.png'
        before = png.stat().st_mtime_ns
        completed = subprocess.run(
            [
                sys.executable,
                '-c',
                'import importlib.util; '
                f'spec = importlib.util.spec_from_file_location("make_ocean_art_import", r"{SCRIPT}"); '
                'module = importlib.util.module_from_spec(spec); '
                'spec.loader.exec_module(module)',
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stdout, '')
        self.assertEqual(png.stat().st_mtime_ns, before)

    def test_load_frame_parses_node_stdout(self):
        payload = b'{"meta": {"cols": 1}, "frame": " ", "colors": []}'
        with patch.object(art.subprocess, 'check_output', return_value=payload) as check:
            frame = art.load_frame()
        check.assert_called_once_with(['node', str(art.RENDERER)])
        self.assertEqual(frame['meta']['cols'], 1)

    def test_blank_glyphs_skip_palette_lookup(self):
        frame = {
            'meta': {'cols': 2, 'rows': 1, 'ground': '#0b0817', 'palette': []},
            'frame': '  ',
            'colors': [],
        }
        image = art.render_image(frame)
        self.assertEqual(image.size, (12, 6))
        self.assertEqual(image.tobytes(), bytes(GROUND) * (image.size[0] * image.size[1]))

    def test_short_rows_keep_the_remaining_cells_blank(self):
        frame = {
            'meta': {'cols': 2, 'rows': 1, 'ground': '#000000', 'palette': ['#ffffff']},
            'frame': '●',
            'colors': [0],
        }
        image = art.render_image(frame)
        self.assertEqual(image.size, (12, 6))
        self.assertEqual(image.getpixel((9, 3)), (0, 0, 0))
        self.assertNotEqual(image.getpixel((3, 3)), (0, 0, 0))

    def test_color_index_is_row_major(self):
        def render(colors):
            frame = {
                'meta': {
                    'cols': 2,
                    'rows': 2,
                    'ground': '#000000',
                    'palette': ['#ff0000', '#0000ff'],
                },
                'frame': '●●\n●●',
                'colors': colors,
            }
            return art.render_image(frame)

        image = render([0, 0, 1, 0])

        def blue(col, row):
            return image.getpixel((col * 6 + 3, row * 6 + 3))[2]

        self.assertGreater(blue(0, 1), blue(1, 0))
        self.assertGreater(blue(0, 1), blue(0, 0))
        self.assertGreater(blue(0, 1), blue(1, 1))

    def test_fixture_pixels_stay_stable(self):
        image = art.render_image(FIXTURE)
        digest = hashlib.sha256(image.tobytes()).hexdigest()
        self.assertEqual(image.size, (18, 12))
        self.assertEqual(digest, FIXTURE_SHA256)
        self.assertEqual(image.getpixel((3, 3)), (185, 2, 7))
        self.assertEqual(image.getpixel((9, 3)), (11, 8, 23))
        self.assertEqual(image.getpixel((15, 3)), (0, 0, 255))
        self.assertEqual(image.getpixel((3, 9)), (0, 248, 0))
        self.assertEqual(image.getpixel((9, 9)), (248, 0, 0))
        self.assertEqual(image.getpixel((15, 9)), (11, 8, 23))

    def test_catalog_metadata_matches_the_checked_in_imageset(self):
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory)
            (catalog / 'Contents.json').write_text('stale\n')
            art.write_catalog(Image.new('RGB', (1, 1)), catalog)
            self.assertEqual(
                (catalog / 'Contents.json').read_text(),
                (BUNDLED / 'Contents.json').read_text(),
            )
            self.assertEqual(
                (catalog / 'OceanSunset.imageset' / 'Contents.json').read_text(),
                (BUNDLED / 'OceanSunset.imageset' / 'Contents.json').read_text(),
            )

    def test_main_writes_the_catalog_and_prints_the_png_path(self):
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory) / 'Artwork.xcassets'
            with (
                patch.object(art, 'CATALOG', catalog),
                patch.object(art, 'load_frame', return_value=FIXTURE),
                redirect_stdout(io.StringIO()) as stdout,
            ):
                art.main()
            image_path = catalog / 'OceanSunset.imageset' / 'OceanSunset.png'
            self.assertEqual(stdout.getvalue(), f'{image_path}\n')
            with Image.open(image_path) as saved:
                self.assertEqual(saved.tobytes(), art.render_image(FIXTURE).tobytes())

    def test_generated_png_matches_the_bundled_file(self):
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory)
            art.write_catalog(art.render_image(art.load_frame()), catalog)
            generated = (catalog / 'OceanSunset.imageset' / 'OceanSunset.png').read_bytes()
            bundled = (BUNDLED / 'OceanSunset.imageset' / 'OceanSunset.png').read_bytes()
            self.assertEqual(generated, bundled)


if __name__ == '__main__':
    unittest.main()
