#!/usr/bin/env python3
"""Behavior tests for scripts/make-icon.py.

Run from the repository root:

    python3 -m unittest scripts/test_make_icon.py
"""

import importlib.util
import shutil
import subprocess
import sys
import tempfile
import unittest
from io import BytesIO
from pathlib import Path

from PIL import Image, UnidentifiedImageError

REPO = Path(__file__).resolve().parents[1]
SCRIPT = Path(__file__).resolve().parent / 'make-icon.py'
CROP = (560, 90, 1060, 590)
CROP_COLOR = (200, 30, 40)
OUTSIDE_COLOR = (0, 0, 80)
LIGHT_COLOR = (240, 220, 180)

WATCHED = (
    REPO / 'App/Assets.xcassets/Contents.json',
    REPO / 'App/Assets.xcassets/AppIcon.appiconset/Contents.json',
    REPO / 'App/Assets.xcassets/AppIcon.appiconset/DaywellIcon.png',
    REPO / 'Shared/ShieldArtwork.xcassets/Contents.json',
    REPO / 'Shared/ShieldArtwork.xcassets/DaywellIcon.imageset/Contents.json',
    REPO / 'Shared/ShieldArtwork.xcassets/DaywellIcon.imageset/DaywellIcon.png',
)

CATALOGS = (
    'App/Assets.xcassets/Contents.json',
    'App/Assets.xcassets/AppIcon.appiconset/Contents.json',
    'Shared/ShieldArtwork.xcassets/Contents.json',
    'Shared/ShieldArtwork.xcassets/DaywellIcon.imageset/Contents.json',
)


def load_make_icon():
    spec = importlib.util.spec_from_file_location('make_icon', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


make_icon = load_make_icon()


def paint_sunset(path, crop_color):
    image = Image.new('RGB', (1200, 600), OUTSIDE_COLOR)
    width = CROP[2] - CROP[0]
    height = CROP[3] - CROP[1]
    image.paste(Image.new('RGB', (width, height), crop_color), (CROP[0], CROP[1]))
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def project_with_artwork(root, crop_color=CROP_COLOR):
    script_dir = root / 'scripts'
    script_dir.mkdir()
    shutil.copy(SCRIPT, script_dir / 'make-icon.py')
    paint_sunset(make_icon.artwork_path(root, 'OceanSunset'), crop_color)
    paint_sunset(make_icon.artwork_path(root, 'OceanSunsetLight'), LIGHT_COLOR)
    return script_dir / 'make-icon.py'


def run_script(script):
    return subprocess.run(
        [sys.executable, str(script)],
        check=True,
        capture_output=True,
        text=True,
    )


def png_bytes(image, optimize):
    buffer = BytesIO()
    image.save(buffer, format='PNG', optimize=optimize)
    return buffer.getvalue()


class RenderTests(unittest.TestCase):
    def test_crop_drops_pixels_outside_the_approved_square(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            paint_sunset(make_icon.artwork_path(root, 'OceanSunset'), CROP_COLOR)
            icon = make_icon.render('OceanSunset', root)

        self.assertEqual(icon.mode, 'RGB')
        self.assertEqual(icon.size, (1024, 1024))
        self.assertEqual(icon.getcolors(maxcolors=1), [(1024 * 1024, CROP_COLOR)])

    def test_render_matches_the_shipped_icon(self):
        rendered = make_icon.render('OceanSunset')
        shipped = (
            REPO / 'App/Assets.xcassets/AppIcon.appiconset/DaywellIcon.png',
            REPO / 'Shared/ShieldArtwork.xcassets/DaywellIcon.imageset/DaywellIcon.png',
        )
        for path in shipped:
            with Image.open(path) as existing:
                self.assertEqual(rendered.size, existing.size)
                self.assertEqual(rendered.tobytes(), existing.convert('RGB').tobytes())


class SaveIfChangedTests(unittest.TestCase):
    def test_writes_a_missing_png(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'DaywellIcon.png'
            image = Image.new('RGB', (4, 4), (3, 4, 5))
            make_icon.save_if_changed(image, path)
            with Image.open(path) as saved:
                self.assertEqual(saved.size, (4, 4))
                self.assertEqual(saved.getpixel((0, 0)), (3, 4, 5))

    def test_keeps_bytes_when_pixels_match(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'DaywellIcon.png'
            image = Image.new('RGB', (32, 32), (8, 16, 24))
            image.save(path, format='PNG', optimize=True)
            original = path.read_bytes()
            modified = path.stat().st_mtime_ns

            plain = Image.new('RGB', (32, 32), (8, 16, 24))
            make_icon.save_if_changed(plain, path)

            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(path.stat().st_mtime_ns, modified)
            self.assertNotEqual(original, png_bytes(plain, optimize=False))

    def test_keeps_opaque_rgba_file_when_rgb_pixels_match(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'DaywellIcon.png'
            Image.new('RGBA', (6, 6), (1, 2, 3, 255)).save(path)
            original = path.read_bytes()
            make_icon.save_if_changed(Image.new('RGB', (6, 6), (1, 2, 3)), path)
            self.assertEqual(path.read_bytes(), original)

    def test_replaces_a_different_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'DaywellIcon.png'
            Image.new('RGB', (4, 4), (1, 1, 1)).save(path)
            make_icon.save_if_changed(Image.new('RGB', (8, 8), (2, 2, 2)), path)
            with Image.open(path) as saved:
                self.assertEqual(saved.size, (8, 8))
                self.assertEqual(saved.getpixel((0, 0)), (2, 2, 2))

    def test_leaves_an_unreadable_file_in_place(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'DaywellIcon.png'
            path.write_text('not a png')
            with self.assertRaises(UnidentifiedImageError):
                make_icon.save_if_changed(Image.new('RGB', (2, 2), (1, 2, 3)), path)
            self.assertEqual(path.read_text(), 'not a png')


class ScriptTests(unittest.TestCase):
    def test_import_does_not_rewrite_shipped_assets(self):
        before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in WATCHED}
        completed = subprocess.run(
            [sys.executable, '-c', (
                'import importlib.util\n'
                'from pathlib import Path\n'
                f'script = Path({str(SCRIPT)!r})\n'
                'spec = importlib.util.spec_from_file_location("make_icon_import", script)\n'
                'module = importlib.util.module_from_spec(spec)\n'
                'spec.loader.exec_module(module)\n'
                'print(module.ROOT)\n'
            )],
            cwd=REPO,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.stdout, f'{REPO}\n')
        self.assertEqual(completed.stderr, '')
        for path, (content, modified) in before.items():
            self.assertEqual(path.read_bytes(), content)
            self.assertEqual(path.stat().st_mtime_ns, modified)

    def test_script_writes_dark_crop_and_catalogs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = project_with_artwork(root)
            completed = run_script(script)

            app_icon = make_icon.app_iconset(root) / 'DaywellIcon.png'
            shield_icon = make_icon.shield_imageset(root) / 'DaywellIcon.png'
            self.assertEqual(completed.stdout, f'{app_icon}\n')
            self.assertEqual(completed.stderr, '')
            self.assertEqual(app_icon.read_bytes(), shield_icon.read_bytes())
            with Image.open(app_icon) as icon:
                self.assertEqual(icon.size, (1024, 1024))
                self.assertEqual(icon.getcolors(maxcolors=1), [(1024 * 1024, CROP_COLOR)])
            for relative in CATALOGS:
                self.assertEqual((root / relative).read_text(), (REPO / relative).read_text())

    def test_second_run_keeps_png_bytes_and_rewrites_catalogs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = project_with_artwork(root)
            run_script(script)

            app_icon = make_icon.app_iconset(root) / 'DaywellIcon.png'
            catalog = make_icon.app_iconset(root) / 'Contents.json'
            original_png = app_icon.read_bytes()
            png_modified = app_icon.stat().st_mtime_ns
            catalog.write_text('{"stale": true}\n')

            run_script(script)

            shipped = REPO / 'App/Assets.xcassets/AppIcon.appiconset/Contents.json'
            self.assertEqual(app_icon.read_bytes(), original_png)
            self.assertEqual(app_icon.stat().st_mtime_ns, png_modified)
            self.assertEqual(catalog.read_text(), shipped.read_text())

    def test_artwork_change_replaces_both_icons(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = project_with_artwork(root)
            run_script(script)
            paint_sunset(make_icon.artwork_path(root, 'OceanSunset'), (9, 90, 200))
            run_script(script)

            for directory in (make_icon.app_iconset(root), make_icon.shield_imageset(root)):
                with Image.open(directory / 'DaywellIcon.png') as icon:
                    self.assertEqual(icon.getcolors(maxcolors=1), [(1024 * 1024, (9, 90, 200))])

    def test_missing_artwork_creates_directories_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script_dir = root / 'scripts'
            script_dir.mkdir()
            script = script_dir / 'make-icon.py'
            shutil.copy(SCRIPT, script)

            completed = subprocess.run(
                [sys.executable, str(script)],
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(completed.returncode, 0)
            self.assertEqual(completed.stdout, '')
            self.assertTrue(make_icon.app_iconset(root).is_dir())
            self.assertTrue(make_icon.shield_imageset(root).is_dir())
            self.assertFalse((make_icon.app_iconset(root) / 'Contents.json').exists())
            self.assertFalse((make_icon.shield_imageset(root) / 'DaywellIcon.png').exists())
            self.assertFalse((root / 'App/Assets.xcassets/Contents.json').exists())


if __name__ == '__main__':
    unittest.main()
