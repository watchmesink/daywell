// Render an upstream ASCII frame without a browser or runtime app dependency.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('./vendor/ascii-rest/ocean-sunset.ts', import.meta.url), 'utf8');
const code = stripTypeScriptTypes(source);
const { default: createFrame, meta } = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const colors = new Uint8Array(meta.cols * meta.rows);
const frame = createFrame()(8, { color: colors });
process.stdout.write(JSON.stringify({ meta, frame, colors: Array.from(colors) }));
