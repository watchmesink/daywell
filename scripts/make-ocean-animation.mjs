// Render the MIT-licensed ascii.rest scene as a silent, seamless local video.
// Development requirements: Node 22.13+ and FFmpeg. No runtime dependencies.
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { fileURLToPath } from 'node:url';

const source = readFileSync(new URL('./vendor/ascii-rest/ocean-sunset.ts', import.meta.url), 'utf8');
const code = stripTypeScriptTypes(source);
const { default: createFrame, meta } = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const render = createFrame();
const colors = new Uint8Array(meta.cols * meta.rows);
const cell = 6, supersampling = 4;
const width = meta.cols * cell, height = meta.rows * cell;
const fps = meta.fps, count = fps * 30, transition = fps;
const rgb = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
const light = process.argv.includes('--light');
const name = light ? 'OceanSunsetLight' : 'OceanSunset';
const ground = rgb(meta.ground);
// Warm paper, coral clouds, golden light, and muted blue water for light mode.
// A subtractive halftone puts larger ink dots in shadows, like a printed scene.
const lightPalette = [
  '#80748e', '#9580a0', '#aa8baa', '#b48eae', '#c592ad',
  '#ce94ae', '#d88fa1', '#df8f98', '#e8948f', '#eda393',
  '#c88798', '#ed9da9', '#f4b2b3', '#b985a0', '#e39a87',
  '#e8a379', '#ecb074', '#eebe75', '#f1cc82', '#f5da99', '#f9e4b5',
  '#b78a89', '#cd9790', '#dea28e',
  '#766c85', '#867992', '#99869f', '#ac90aa', '#bc9cb3',
  '#f0b59a', '#f4c7ad', '#f7d7bf',
  '#708da3', '#7696a8', '#7b9faa', '#84a9b0', '#93b6b6',
  '#75a1b0', '#88b5bc',
  '#ac94b1', '#bba0ba', '#cbaec7', '#ddc1d2'
];
if (lightPalette.length !== meta.palette.length) throw new Error('Light palette must match the source palette');
const mix = (a, b, t) => a.map((channel, i) => Math.round(channel + (b[i] - channel) * t));
const paperAt = row => row < 56
  ? mix(rgb('#f0dce5'), rgb('#ffe4bd'), row / 55)
  : mix(rgb('#e5e8d7'), rgb('#bfd7dc'), (row - 56) / 43);
const radii = { ' ': 0, '·': 0.12, '•': 0.27, '●': 0.44 };

// Pre-render tiny antialiased dot tiles, then copy them into each frame.
const makeTiles = (palette, paper, sizes, inkScale = 1) => palette.map(hex => Object.fromEntries(Object.entries(sizes).map(([glyph, radius]) => {
  const color = rgb(hex).map(channel => Math.round(channel * inkScale)), tile = Buffer.alloc(cell * cell * 3);
  for (let y = 0; y < cell; y++) for (let x = 0; x < cell; x++) {
    let coverage = 0;
    for (let sy = 0; sy < supersampling; sy++) for (let sx = 0; sx < supersampling; sx++) {
      const dx = x + (sx + 0.5) / supersampling - cell / 2;
      const dy = y + (sy + 0.5) / supersampling - cell / 2;
      if (dx * dx + dy * dy < (radius * cell) ** 2) coverage++;
    }
    const alpha = coverage / (supersampling * supersampling);
    for (let c = 0; c < 3; c++) tile[(y * cell + x) * 3 + c] = Math.round(paper[c] + (color[c] - paper[c]) * alpha);
  }
  return [glyph, tile];
})));
const tiles = makeTiles(meta.palette, ground, radii);
const lightTiles = light ? Array.from({ length: meta.rows }, (_, row) =>
  // A wider range of dot sizes separates shadows from sunlight. Deeper ink
  // defines the clouds, headland, and waves while the paper stays pastel.
  makeTiles(lightPalette, paperAt(row), { ' ': 0.48, '·': 0.4, '•': 0.25, '●': 0.07 }, 0.8)) : null;

const directory = new URL('../App/Resources/', import.meta.url);
mkdirSync(directory, { recursive: true });
const output = fileURLToPath(new URL(`${name}.mp4`, directory));
const encoder = spawn('ffmpeg', [
  '-hide_banner', '-loglevel', 'error', '-y',
  '-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', `${width}x${height}`,
  '-framerate', String(fps), '-i', 'pipe:0', '-an',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p',
  '-movflags', '+faststart', output
], { stdio: ['pipe', 'inherit', 'inherit'] });
const completion = once(encoder, 'close');
const opening = [];
for (let frame = 0; frame < count; frame++) {
  const glyphs = render(8 + frame / fps, { color: colors }).replaceAll('\n', '');
  const pixels = Buffer.alloc(width * height * 3);
  for (let index = 0; index < glyphs.length; index++) {
    const rowTiles = light ? lightTiles[Math.floor(index / meta.cols)] : tiles;
    const tile = rowTiles[colors[index]][glyphs[index]];
    const x = (index % meta.cols) * cell, y = Math.floor(index / meta.cols) * cell;
    for (let row = 0; row < cell; row++) {
      tile.copy(pixels, ((y + row) * width + x) * 3, row * cell * 3, (row + 1) * cell * 3);
    }
  }
  if (frame < transition) {
    opening.push(pixels);
    continue;
  }
  // Blend the last second into the opening second; the next loop continues
  // with its following frame, without a jump or reversing the waves.
  if (frame >= count - transition) {
    const index = frame - (count - transition), alpha = (index + 1) / transition;
    const first = opening[index];
    for (let i = 0; i < pixels.length; i++) pixels[i] = Math.round(pixels[i] * (1 - alpha) + first[i] * alpha);
  }
  if (!encoder.stdin.write(pixels)) await once(encoder.stdin, 'drain');
}
encoder.stdin.end();
const [status] = await completion;
if (status !== 0) throw new Error(`FFmpeg exited with status ${status}`);
console.log(`${output}: ${width}×${height}, ${fps} fps, ${(count - transition) / fps}s, no audio`);

const fadeLaunchImage = (input, output, background) => {
  const decoded = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', input,
    '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', 'pipe:1'], { maxBuffer: width * height * 3 * 2 });
  if (decoded.status !== 0 || decoded.stdout.length !== width * height * 3) {
    throw new Error('Could not decode the launch artwork');
  }
  const pixels = decoded.stdout, paper = rgb(background);
  for (let row = 0; row < height; row++) {
    const position = row / (height - 1);
    // Match the runtime backdrop mask: clear edges, a fully visible center.
    const alpha = Math.min(1, position / 0.16, (1 - position) / 0.26);
    for (let col = 0; col < width; col++) for (let channel = 0; channel < 3; channel++) {
      const index = (row * width + col) * 3 + channel;
      pixels[index] = Math.round(paper[channel] + (pixels[index] - paper[channel]) * alpha);
    }
  }
  const encoded = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y',
    '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-video_size', `${width}x${height}`, '-i', 'pipe:0',
    '-frames:v', '1', output], { input: pixels });
  if (encoded.status !== 0) throw new Error('Could not encode the faded launch artwork');
};

if (light) {
  const asset = new URL('../Shared/Artwork.xcassets/OceanSunsetLight.imageset/', import.meta.url);
  mkdirSync(asset, { recursive: true });
  const imagePath = fileURLToPath(new URL('OceanSunsetLight.png', asset));
  const still = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', output,
    '-frames:v', '1', imagePath], { stdio: 'inherit' });
  if (still.status !== 0) throw new Error('Could not render the light-theme fallback');
  writeFileSync(new URL('Contents.json', asset), JSON.stringify({
    images: [{ filename: 'OceanSunsetLight.png', idiom: 'universal' }],
    info: { author: 'xcode', version: 1 }
  }, null, 2) + '\n');

  // Storyboard launch screens select catalog appearances before app code runs.
  // Keep both the native launch and SwiftUI loading view on these same stills.
  const launchAsset = new URL('../Shared/Artwork.xcassets/LaunchArtwork.imageset/', import.meta.url);
  mkdirSync(launchAsset, { recursive: true });
  fadeLaunchImage(imagePath, fileURLToPath(new URL('OceanSunsetLight.png', launchAsset)), '#f2f2f7');
  fadeLaunchImage(fileURLToPath(new URL('../Shared/Artwork.xcassets/OceanSunset.imageset/OceanSunset.png', import.meta.url)),
    fileURLToPath(new URL('OceanSunset.png', launchAsset)), '#0b0817');
  writeFileSync(new URL('Contents.json', launchAsset), JSON.stringify({
    images: [
      { filename: 'OceanSunsetLight.png', idiom: 'universal' },
      { filename: 'OceanSunset.png', idiom: 'universal', appearances: [{ appearance: 'luminosity', value: 'dark' }] }
    ],
    info: { author: 'xcode', version: 1 }
  }, null, 2) + '\n');
}
