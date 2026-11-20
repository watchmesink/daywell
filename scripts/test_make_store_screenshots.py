#!/usr/bin/env python3
"""Behavior tests for scripts/make-store-screenshots.py.

Run with: python3 scripts/test_make_store_screenshots.py
Requires Pillow. Does not read or write the repository's capture or screenshot folders.
"""
import importlib.util
import io
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts' / 'make-store-screenshots.py'
VARIABLE_FONTS = (
    '/System/Library/Fonts/SFNS.ttf',
    '/usr/share/fonts/truetype/cascadia/CascadiaCode.ttf',
)


def load():
    spec = importlib.util.spec_from_file_location('make_store_screenshots', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CountFont:
    """One unit of width per character, including spaces."""

    def getlength(self, text):
        return len(text)


def reference_background(size, theme):
    """Original sunset backdrop, kept here as the pixel oracle."""
    width, height = size
    top, bottom = theme['top'], theme['bottom']
    column = Image.new('RGB', (1, height))
    for y in range(height):
        blend = y / (height - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * blend) for a, b in zip(top, bottom)))
    canvas = column.resize(size)
    glow = Image.new('L', size, 0)
    radius = int(width * 0.62)
    ImageDraw.Draw(glow).ellipse(
        (width // 2 - radius, int(height * 0.12) - radius,
         width // 2 + radius, int(height * 0.12) + radius),
        fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(width * 0.18))
    canvas.paste(Image.new('RGB', size, theme['sun']), mask=glow)
    return canvas


def reference_mask(size, radius, scale=4):
    big = Image.new('L', (size[0] * scale, size[1] * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, big.width - 1, big.height - 1), radius * scale, fill=255)
    return big.resize(size, Image.Resampling.LANCZOS)


def reference_phone(size):
    width = size[0]
    unit = width / 1206
    bezel = round(26 * unit)
    phone_width = width - 2 * round(83 * unit)
    screen_width = phone_width - 2 * bezel
    scale = screen_width / 1206
    screen_height = round(2622 * scale)
    return (
        unit, bezel, phone_width, screen_height + 2 * bezel, screen_width, screen_height,
        (width - phone_width) // 2, round(700 * unit), round(186 * scale),
    )


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load()

    def test_paths_sizes_and_frame_color(self):
        module = self.module
        self.assertEqual(module.ROOT, ROOT)
        self.assertEqual(module.CAPTURES, ROOT / 'build/store-captures')
        self.assertEqual(module.OUT, ROOT / 'publishing/screenshots')
        self.assertEqual(module.FONT, '/System/Library/Fonts/SFNS.ttf')
        self.assertEqual(module.SOURCE_SIZE, (1206, 2622))
        self.assertEqual(list(module.SIZES), ['6.3-inch', '6.9-inch'])
        self.assertEqual(module.SIZES['6.3-inch'], (1206, 2622))
        self.assertEqual(module.SIZES['6.9-inch'], (1320, 2868))
        self.assertEqual(module.FRAME_COLOR, (22, 22, 26))
        self.assertEqual(module.THUMBNAIL, (402, 874))
        self.assertEqual(module.CONTACT_GAP, 24)

    def test_themes(self):
        self.assertEqual(self.module.THEMES, {
            'light': {'ink': (14, 10, 28), 'soft': (84, 76, 100), 'top': (252, 233, 216),
                      'bottom': (204, 206, 221), 'sun': (255, 222, 168), 'shadow': (40, 30, 60)},
            'dark': {'ink': (255, 255, 255), 'soft': (206, 196, 214), 'top': (30, 21, 46),
                     'bottom': (11, 8, 23), 'sun': (96, 52, 70), 'shadow': (0, 0, 0)},
        })

    def test_slides_and_theme_lookup(self):
        module = self.module
        self.assertEqual(list(module.SLIDES), [
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
             'One screen shows what\u2019s blocked, when, and today\u2019s usage.'),
            ('05-private', 'apps-dark.png',
             'Private\nby default.',
             'Daywell never sees which apps you chose. Your rules stay on your iPhone.'),
            ('06-your-routine', 'allowance-dark.png',
             'Your time.\nYour routine.',
             'Set daily blocks and a shared allowance that fit your day.'),
        ])
        self.assertIs(module.theme_of('apps-light.png'), module.THEMES['light'])
        self.assertIs(module.theme_of('dashboard-dark.png'), module.THEMES['dark'])
        self.assertIs(module.theme_of('nested/allowance-light.png'), module.THEMES['light'])
        with self.assertRaises(KeyError):
            module.theme_of('apps-blue.png')


class TextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load()
        cls.face = CountFont()

    def test_wrap_keeps_a_short_line_and_empty_text(self):
        wrap = self.module.wrap
        self.assertEqual(wrap('aa bb', self.face, 5), ['aa bb'])
        self.assertEqual(wrap('', self.face, 5), [''])
        self.assertEqual(wrap('   ', self.face, 5), [''])
        self.assertEqual(wrap('\n', self.face, 10), ['', ''])

    def test_wrap_balances_two_lines_and_leaves_longer_wraps_alone(self):
        wrap = self.module.wrap
        self.assertEqual(wrap('aaa bbb ccc ddd', self.face, 12), ['aaa bbb', 'ccc ddd'])
        self.assertEqual(wrap('aa bb cc dd ee', self.face, 5), ['aa bb', 'cc dd', 'ee'])
        self.assertEqual(wrap('abcdef ghijkl', self.face, 5), ['abcdef', 'ghijkl'])

    def test_wrap_honors_forced_breaks(self):
        wrap = self.module.wrap
        self.assertEqual(wrap('aa bb\ncc dd ee', self.face, 5), ['aa bb', 'cc dd', 'ee'])
        self.assertEqual(wrap('aa\nbb', self.face, 100), ['aa', 'bb'])
        self.assertEqual(wrap('aa\n', self.face, 100), ['aa', ''])

    def test_wrap_preserves_every_word_in_the_catalog(self):
        wrap = self.module.wrap
        for slide in self.module.SLIDES:
            for text in (slide.headline, slide.subheadline):
                lines = wrap(text, self.face, 28)
                self.assertEqual(
                    [word for line in lines for word in line.split()],
                    text.replace('\n', ' ').split())

    def test_fitted_does_not_shrink_text_without_a_forced_break(self):
        sizes = []

        def fake(size, weight):
            sizes.append((size, weight))

            class Face:
                def getlength(self, text, size=size):
                    return len(text) * size

            return Face()

        self.module.font = fake
        _face, lines = self.module.fitted('aa bb cc', 20, 'Bold', 10)
        self.assertEqual(lines, ['aa', 'bb', 'cc'])
        self.assertEqual(sizes, [(20, 'Bold')])

    def test_fitted_keeps_a_headline_that_already_fits(self):
        sizes = []
        self.module.font = self._metric(sizes)
        _face, lines = self.module.fitted('aa bb\ncc dd', 40, 'Bold', 200)
        self.assertEqual(lines, ['aa bb', 'cc dd'])
        self.assertEqual(sizes, [(40, 'Bold')])

    def test_fitted_shrinks_by_two_until_each_forced_line_fits(self):
        sizes = []
        self.module.font = self._metric(sizes)
        _face, lines = self.module.fitted('aa bb\ncc dd', 44, 'Regular', 200)
        self.assertEqual(lines, ['aa bb', 'cc dd'])
        self.assertEqual(sizes, [(44, 'Regular'), (42, 'Regular'), (40, 'Regular')])

    def test_fitted_stops_once_the_size_drops_below_forty(self):
        sizes = []
        self.module.font = self._metric(sizes)
        _face, lines = self.module.fitted('aa bb\ncc dd', 42, 'Bold', 10)
        self.assertEqual(sizes, [(42, 'Bold'), (40, 'Bold'), (38, 'Bold')])
        self.assertGreater(len(lines), 2)

        sizes.clear()
        self.module.fitted('aa bb\ncc dd', 41, 'Bold', 10)
        self.assertEqual([size for size, _weight in sizes], [41, 39])

        sizes.clear()
        self.module.fitted('aa bb\ncc dd', 30, 'Bold', 10)
        self.assertEqual(sizes, [(30, 'Bold')])

    def test_fitted_terminates_for_every_catalog_headline(self):
        self.module.font = lambda size, weight: ImageFont.load_default(size)
        for slide in self.module.SLIDES:
            for width in (900, 1100):
                _face, lines = self.module.fitted(slide.headline, 110, 'Bold', width)
                self.assertTrue(lines)
                self.assertTrue(all(isinstance(line, str) for line in lines))

    def _metric(self, sizes):
        def fake(size, weight):
            sizes.append((size, weight))

            class Face:
                def getlength(self, text, size=size):
                    return len(text) * size

            return Face()

        return fake


class FontTests(unittest.TestCase):
    def test_missing_font_file_is_not_swallowed(self):
        module = load()
        module.FONT = '/no/such/font.ttf'
        with self.assertRaises(OSError):
            module.font(12, 'Regular')

    def test_variation_name_is_retried_as_bytes(self):
        for error in (OSError, ValueError):
            with self.subTest(error=error.__name__):
                calls = []

                def reject_str(name, error=error):
                    calls.append(name)
                    if isinstance(name, str):
                        raise error('use bytes')

                module = load()
                self._install(module, reject_str)
                self.assertIs(module.font(16, 'Bold'), module.ImageFont.truetype.face)
                self.assertEqual(calls, ['Bold', b'Bold'])

    def test_other_variation_errors_are_not_retried(self):
        calls = []

        def reject(name):
            calls.append(name)
            raise TypeError('unexpected')

        module = load()
        self._install(module, reject)
        with self.assertRaises(TypeError):
            module.font(16, 'Bold')
        self.assertEqual(calls, ['Bold'])

    def test_bytes_variation_failure_propagates(self):
        calls = []

        def reject(name):
            calls.append(name)
            raise OSError('unavailable')

        module = load()
        self._install(module, reject)
        with self.assertRaises(OSError):
            module.font(16, 'Regular')
        self.assertEqual(calls, ['Regular', b'Regular'])

    def test_named_variation_loads_from_an_installed_variable_font(self):
        module = load()
        for candidate in (module.FONT, *VARIABLE_FONTS):
            if Path(candidate).exists():
                module.FONT = candidate
                break
        else:
            self.skipTest('no variable font installed')
        for weight in ('Regular', 'Bold'):
            face = module.font(36, weight)
            self.assertIsInstance(face, ImageFont.FreeTypeFont)
            self.assertGreater(face.getlength('Daywell'), 0)

    def _install(self, module, setter):
        class Dummy:
            def set_variation_by_name(self, name):
                setter(name)

        face = Dummy()

        def truetype(path, size):
            truetype.face = face
            return face

        module.ImageFont = SimpleNamespace(truetype=truetype)


class PaintingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load()

    def test_background_matches_the_sunset_oracle(self):
        for size in ((32, 48), (63, 90), (120, 80)):
            for theme in self.module.THEMES.values():
                got = self.module.background(size, theme)
                self.assertEqual(got.mode, 'RGB')
                self.assertEqual(got.tobytes(), reference_background(size, theme).tobytes())

    def test_cached_background_is_not_shared_across_callers(self):
        theme = self.module.THEMES['light']
        first = self.module.background((48, 64), theme)
        first.putpixel((0, 0), (1, 2, 3))
        second = self.module.background((48, 64), theme)
        self.assertEqual(second.tobytes(), reference_background((48, 64), theme).tobytes())
        self.assertNotEqual(first.getpixel((0, 0)), second.getpixel((0, 0)))

    def test_rounded_mask_matches_the_supersampled_oracle(self):
        cases = [((40, 60), 12), ((40, 60), 12, 1), ((33, 33), 0), ((80, 20), 8, 3)]
        for args in cases:
            mask = self.module.rounded_mask(*args)
            self.assertEqual(mask.mode, 'L')
            self.assertEqual(mask.tobytes(), reference_mask(*args).tobytes())
        mask = self.module.rounded_mask((50, 70), 16)
        self.assertEqual(mask.getpixel((0, 0)), 0)
        self.assertEqual(mask.getpixel((25, 35)), 255)
        mask.putpixel((25, 35), 0)
        fresh = self.module.rounded_mask((50, 70), 16)
        self.assertEqual(fresh.tobytes(), reference_mask((50, 70), 16).tobytes())

    def test_phone_geometry_is_independent_of_canvas_height(self):
        module = self.module
        for size in ((1206, 2622), (1320, 2868), (1000, 1800), (806, 100)):
            self.assertEqual(module.phone_geometry(size), reference_phone(size))
        self.assertEqual(module.phone_geometry((1206, 10)), module.phone_geometry((1206, 9999)))

    def test_compose_frames_the_capture_without_alpha(self):
        module = self.module
        module.font = lambda size, weight: ImageFont.load_default(size)
        capture = Image.new('RGB', module.SOURCE_SIZE, (240, 10, 10))
        size = (480, 1044)
        light = module.compose(size, capture, module.THEMES['light'], 'Hello\nthere', 'A short line.')
        again = module.compose(size, capture, module.THEMES['light'], 'Hello\nthere', 'A short line.')
        dark = module.compose(size, capture, module.THEMES['dark'], 'Hello\nthere', 'A short line.')
        phone = module.phone_geometry(size)
        center = (phone.x + phone.bezel + phone.screen_width // 2,
                  phone.top + phone.bezel + phone.screen_height // 2)
        bezel = (phone.x + phone.bezel // 2, phone.top + phone.height // 2)
        self.assertEqual(light.size, size)
        self.assertEqual(light.mode, 'RGB')
        self.assertEqual(light.tobytes(), again.tobytes())
        self.assertNotEqual(light.tobytes(), dark.tobytes())
        self.assertEqual(light.getpixel(center), (240, 10, 10))
        self.assertEqual(light.getpixel(bezel), module.FRAME_COLOR)


class MainTests(unittest.TestCase):
    def setUp(self):
        self.module = load()
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.captures = root / 'captures'
        self.out = root / 'out'
        self.captures.mkdir()
        self.module.CAPTURES = self.captures
        self.module.OUT = self.out
        self.seen = []

    def test_full_run_replaces_pngs_and_writes_the_contact_sheet(self):
        self.write_captures()
        self.use_flat_compose()
        for folder in self.module.SIZES:
            directory = self.out / folder
            directory.mkdir(parents=True)
            (directory / 'stale.png').write_bytes(b'old')
            (directory / 'STALE.PNG').write_bytes(b'KEEP')
            (directory / 'note.txt').write_text('keep')
        saves = self.record_saves()
        text = self.render([])

        self.assertEqual(text, self.expected_stdout([]))
        self.assertTrue(all(kwargs == {'optimize': True} for kwargs in saves))
        for folder, size in self.module.SIZES.items():
            directory = self.out / folder
            self.assertEqual((directory / 'STALE.PNG').read_bytes(), b'KEEP')
            self.assertEqual((directory / 'note.txt').read_text(), 'keep')
            self.assertFalse((directory / 'stale.png').exists())
            for index, slide in enumerate(self.module.SLIDES, start=1):
                image = Image.open(directory / f'{slide.slug}.png')
                self.assertEqual(image.size, size)
                self.assertEqual(image.mode, 'RGB')
                self.assertEqual(image.getpixel((0, 0)), (index, 20, 30))
        sheet = Image.open(self.out / 'contact-sheet.png')
        self.assertEqual(sheet.mode, 'RGB')
        self.assertEqual(sheet.size, (6 * (402 + 24) + 24, 874 + 2 * 24))
        self.assertEqual(sheet.getpixel((24, 24)), (1, 20, 30))
        self.assertEqual(sheet.getpixel((24 + 401, 24 + 873)), (1, 20, 30))
        self.assertEqual(sheet.getpixel((24 + 402, 24)), (255, 255, 255))
        self.assertEqual(sheet.getpixel((24, 24 + 874)), (255, 255, 255))
        last = 24 + 5 * (402 + 24)
        self.assertEqual(sheet.getpixel((last, 24)), (6, 20, 30))
        self.assertEqual(sheet.getpixel((last + 402, 24)), (255, 255, 255))
        self.assertEqual([mode for _headline, _ink, mode, _size in self.seen], ['RGB'] * 12)

    def test_selected_slugs_keep_catalog_order_and_existing_pngs(self):
        self.write_captures()
        self.use_flat_compose()
        folder = self.out / '6.3-inch'
        folder.mkdir(parents=True)
        (folder / 'stale.png').write_bytes(b'old')
        text = self.render(['06-your-routine', '01-choose-apps', '01-choose-apps'])

        self.assertEqual(text, self.expected_stdout(['06-your-routine', '01-choose-apps']))
        self.assertEqual((folder / 'stale.png').read_bytes(), b'old')
        names = sorted(path.name for path in folder.glob('*.png'))
        self.assertEqual(names, ['01-choose-apps.png', '06-your-routine.png', 'stale.png'])
        sheet = Image.open(self.out / 'contact-sheet.png')
        self.assertEqual(sheet.size, (2 * (402 + 24) + 24, 874 + 2 * 24))
        self.assertEqual(sheet.getpixel((24, 24)), (1, 20, 30))
        self.assertEqual(sheet.getpixel((24 + 402 + 24, 24)), (6, 20, 30))

    def test_unknown_slug_creates_folders_without_touching_existing_output(self):
        self.out.mkdir()
        marker = self.out / 'contact-sheet.png'
        marker.write_bytes(b'keep')
        folder = self.out / '6.3-inch'
        folder.mkdir()
        (folder / 'stale.png').write_bytes(b'old')
        text = self.render(['nope'])
        self.assertEqual(text, '')
        self.assertEqual(marker.read_bytes(), b'keep')
        self.assertEqual((folder / 'stale.png').read_bytes(), b'old')
        self.assertTrue((self.out / '6.9-inch').is_dir())
        self.assertEqual(self.seen, [])

    def test_wrong_capture_size_reports_the_file_and_stops(self):
        self.write_captures(size=(4, 5))
        folder = self.out / '6.3-inch'
        folder.mkdir(parents=True)
        (folder / 'stale.png').write_bytes(b'old')
        with self.assertRaises(AssertionError) as caught:
            self.render([])
        self.assertEqual(str(caught.exception), 'apps-light.png: (4, 5)')
        self.assertFalse((folder / 'stale.png').exists())
        self.assertFalse((folder / '01-choose-apps.png').exists())
        self.assertFalse((self.out / '6.9-inch').exists())
        self.assertFalse((self.out / 'contact-sheet.png').exists())

    def test_filtered_wrong_size_names_the_requested_capture(self):
        self.write_captures(size=(9, 8))
        with self.assertRaises(AssertionError) as caught:
            self.render(['03-shared-allowance'])
        self.assertEqual(str(caught.exception), 'allowance-light.png: (9, 8)')
        self.assertFalse((self.out / 'contact-sheet.png').exists())

    def test_rgba_captures_are_converted_before_composition(self):
        self.write_captures(mode='RGBA')
        self.use_flat_compose()
        self.render(['05-private'])
        self.assertEqual(self.seen, [
            ('Private\nby default.', self.module.THEMES['dark']['ink'], 'RGB', self.module.SOURCE_SIZE),
            ('Private\nby default.', self.module.THEMES['dark']['ink'], 'RGB', self.module.SOURCE_SIZE),
        ])

    def write_captures(self, size=None, mode='RGB'):
        size = self.module.SOURCE_SIZE if size is None else size
        color = {'RGB': (12, 34, 56), 'RGBA': (12, 34, 56, 80), 'L': 40}[mode]
        for slide in self.module.SLIDES:
            Image.new(mode, size, color).save(self.captures / slide.capture)

    def use_flat_compose(self):
        slides = list(self.module.SLIDES)

        def compose(size, capture, theme, headline, sub):
            self.seen.append((headline, theme['ink'], capture.mode, capture.size))
            index = next(i for i, slide in enumerate(slides, start=1) if slide.headline == headline)
            return Image.new('RGB', size, (index, 20, 30))

        self.module.compose = compose

    def record_saves(self):
        saves = []
        real_save = Image.Image.save

        def save(image, fp, **kwargs):
            saves.append(kwargs)
            return real_save(image, fp, **kwargs)

        Image.Image.save = save
        self.addCleanup(lambda: setattr(Image.Image, 'save', real_save))
        return saves

    def render(self, slugs):
        previous = self.module.sys.argv
        self.module.sys.argv = ['make-store-screenshots.py', *slugs]
        buffer = io.StringIO()
        try:
            with redirect_stdout(buffer):
                self.module.main()
        finally:
            self.module.sys.argv = previous
        return buffer.getvalue()

    def expected_stdout(self, slugs):
        chosen = [slide for slide in self.module.SLIDES if not slugs or slide.slug in slugs]
        lines = []
        for folder, size in self.module.SIZES.items():
            for slide in chosen:
                lines.append(f'{self.out / folder / (slide.slug + ".png")} {size}')
        if chosen:
            sheet = (len(chosen) * (402 + 24) + 24, 874 + 2 * 24)
            lines.append(f'{self.out / "contact-sheet.png"} {sheet}')
        return '\n'.join(lines) + ('\n' if lines else '')


if __name__ == '__main__':
    unittest.main()
