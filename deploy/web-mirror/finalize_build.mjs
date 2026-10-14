// The web build's heaviest files, named by their content and compressed
// once more for the nginx mirror (deploy/web-mirror/nginx.conf). Node's own
// modules only: nothing is installed.
//
//   node deploy/web-mirror/finalize_build.mjs version  apps/mobile/build/web
//   node deploy/web-mirror/finalize_build.mjs compress <site>/nukhbaa
//
// version -- before GitHub Pages and the mirror take the build:
//   * main.dart.js becomes main.dart.<sha256, 12 hex>.js and the build
//     config in flutter_bootstrap.js names it (mainJsPath);
//   * canvaskit/ becomes canvaskit-<engine revision, 12 hex>/ and the
//     loader is told where it is (config.canvasKitBaseUrl). The engine
//     revision names the CanvasKit build exactly.
//   A new build that changes their bytes gives them new names, so the
//   mirror lets a browser keep them a year without asking again. index.html
//   and flutter_bootstrap.js keep fixed names and stay no-cache: they bring
//   the new names to a returning visitor (batch 72).
//
// compress -- the mirror only (GitHub Pages compresses on its own): a .br
//   copy at quality 11 of what a first visit waits for -- main.dart.<hash>.js,
//   canvaskit-<rev>/canvaskit.{js,wasm}, canvaskit-<rev>/chromium/
//   canvaskit.{js,wasm} and the fonts. What Chrome fetched from the build
//   of e0f5239 went from 4.01 MB in gzip to 3.01 MB in brotli.
//
// Every expectation is checked before the first file moves; a build that
// does not look as expected stops the deploy rather than going out half
// renamed.

import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

function fail(message) {
  console.error(`finalize_build: ${message}`);
  process.exit(1);
}

function exactlyOnce(text, needle, what) {
  const first = text.indexOf(needle);
  if (first < 0) fail(`flutter_bootstrap.js has no ${what} (${needle})`);
  if (text.indexOf(needle, first + 1) >= 0) {
    fail(`flutter_bootstrap.js has more than one ${what} (${needle})`);
  }
}

function version(dir) {
  const bootPath = path.join(dir, 'flutter_bootstrap.js');
  if (!fs.existsSync(bootPath)) fail(`no ${bootPath}`);
  const boot = fs.readFileSync(bootPath, 'utf8');

  const revisions = [...boot.matchAll(/"engineRevision":"([0-9a-f]{40})"/g)];
  if (revisions.length !== 1) fail('expected one engineRevision in the build config');
  exactlyOnce(boot, '"useLocalCanvasKit":true', 'local CanvasKit flag (--no-web-resources-cdn)');
  exactlyOnce(boot, '"mainJsPath":"main.dart.js"', 'mainJsPath');
  exactlyOnce(boot, '_flutter.loader.load({', 'loader call');
  if (boot.includes('config: { canvasKitBaseUrl: "')) fail('already done: the loader call names the CanvasKit folder');

  const kitFrom = path.join(dir, 'canvaskit');
  const kitName = `canvaskit-${revisions[0][1].slice(0, 12)}`;
  for (const f of ['canvaskit.js', 'canvaskit.wasm', 'chromium/canvaskit.js', 'chromium/canvaskit.wasm']) {
    if (!fs.existsSync(path.join(kitFrom, f))) fail(`no canvaskit/${f}`);
  }
  if (fs.existsSync(path.join(dir, kitName))) fail(`${kitName} already exists`);

  const mainFrom = path.join(dir, 'main.dart.js');
  if (!fs.existsSync(mainFrom)) fail('no main.dart.js');
  // dart2js names deferred parts after the entry point (main.dart.js_N.part.js)
  // and loads them by that name; renaming the entry point would orphan them.
  const parts = fs.readdirSync(dir).filter((f) => f.startsWith('main.dart.js_'));
  if (parts.length) fail(`deferred parts present (${parts.join(', ')}): not renamed`);
  const mainHash = createHash('sha256').update(fs.readFileSync(mainFrom)).digest('hex').slice(0, 12);
  const mainName = `main.dart.${mainHash}.js`;

  const updated = boot
    .replace('"mainJsPath":"main.dart.js"', `"mainJsPath":"${mainName}"`)
    .replace('_flutter.loader.load({', `_flutter.loader.load({\n  config: { canvasKitBaseUrl: "${kitName}/" },`);

  fs.renameSync(kitFrom, path.join(dir, kitName));
  fs.renameSync(mainFrom, path.join(dir, mainName));
  fs.writeFileSync(bootPath, updated);
  console.log(`finalize_build: ${mainName}, ${kitName}/`);
}

function onlyMatch(dir, pattern, what) {
  const found = fs.readdirSync(dir).filter((f) => pattern.test(f));
  if (found.length !== 1) fail(`expected one ${what} in ${dir}, found ${found.length}`);
  return found[0];
}

function fontsIn(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => /\.(ttf|otf)$/.test(f))
    .map((f) => path.join(dir, f));
}

function compress(dir) {
  const main = onlyMatch(dir, /^main\.dart\.[0-9a-f]{12}\.js$/, 'main.dart.<hash>.js (run version first)');
  const kit = onlyMatch(dir, /^canvaskit-[0-9a-f]{12}$/, 'canvaskit-<revision> folder');
  const files = [
    path.join(dir, main),
    ...['canvaskit.js', 'canvaskit.wasm', 'chromium/canvaskit.js', 'chromium/canvaskit.wasm'].map((f) =>
      path.join(dir, kit, f),
    ),
    ...fontsIn(path.join(dir, 'assets', 'fonts')),
    ...fontsIn(path.join(dir, 'assets', 'assets', 'fonts')),
  ];
  let before = 0;
  let after = 0;
  for (const file of files) {
    if (!fs.existsSync(file)) fail(`no ${file}`);
    const bytes = fs.readFileSync(file);
    const packed = zlib.brotliCompressSync(bytes, {
      params: {
        [zlib.constants.BROTLI_PARAM_QUALITY]: 11,
        [zlib.constants.BROTLI_PARAM_SIZE_HINT]: bytes.length,
      },
    });
    if (!zlib.brotliDecompressSync(packed).equals(bytes)) fail(`${file}: the .br copy does not decode back`);
    fs.writeFileSync(`${file}.br`, packed);
    before += zlib.gzipSync(bytes, { level: 6 }).length;
    after += packed.length;
  }
  console.log(
    `finalize_build: ${files.length} .br copies; gzip ${(before / 1048576).toFixed(2)} MB -> brotli ${(after / 1048576).toFixed(2)} MB`,
  );
}

const [mode, dir] = process.argv.slice(2);
if (!dir || !fs.existsSync(dir)) fail('usage: finalize_build.mjs version|compress <web build folder>');
if (mode === 'version') version(dir);
else if (mode === 'compress') compress(dir);
else fail(`unknown mode ${mode}`);
