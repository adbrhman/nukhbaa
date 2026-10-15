// Asks the mirror image itself (the Dockerfile Northflank builds from
// web-dist, run on the CI runner) for the build it is about to publish,
// the way a browser would, and stops the deploy on any wrong answer:
//
//   node deploy/web-mirror/check_mirror.mjs http://127.0.0.1:8080 <site>
//
// * each .br-compressed file: with br it comes back br, with gzip it comes
//   back gzip, with neither it comes back plain -- and each decodes to the
//   very bytes on disk, with its type and its cache rule;
// * a content-named file without a .br copy: never br, kept a year;
// * index.html and flutter_bootstrap.js: no-cache, the bootstrap naming
//   the files that exist;
// * an old content name: 404, never the app page; a .br name asked for
//   directly: 404; a deep link: the app page;
// * a team crest: kept a week (audit L-54).
// Node's own modules only.

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import zlib from 'node:zlib';

const [base, site] = process.argv.slice(2);
if (!base || !site) {
  console.error('usage: check_mirror.mjs <base url> <site folder>');
  process.exit(1);
}
const app = path.join(site, 'nukhbaa');
const YEAR = 'public, max-age=31536000, immutable';
const MONTH = 'public, max-age=2592000';
const WEEK = 'public, max-age=604800';
const problems = [];
let checks = 0;

function get(urlPath, acceptEncoding) {
  return new Promise((resolve, reject) => {
    const headers = acceptEncoding == null ? {} : { 'Accept-Encoding': acceptEncoding };
    const req = http.get(new URL(urlPath, base), { headers }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
    });
    req.on('error', reject);
    req.setTimeout(30000, () => req.destroy(new Error(`timeout on ${urlPath}`)));
  });
}

function expect(ok, message) {
  checks += 1;
  if (!ok) problems.push(message);
}

function decode(res) {
  const enc = res.headers['content-encoding'];
  if (enc === 'br') return zlib.brotliDecompressSync(res.body);
  if (enc === 'gzip') return zlib.gunzipSync(res.body);
  return res.body;
}

async function waitForServer() {
  for (let i = 0; i < 60; i += 1) {
    try {
      const res = await get('/nukhbaa/', 'identity');
      if (res.status === 200) return;
    } catch {
      // not listening yet
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  console.error(`check_mirror: ${base} did not answer within 30 s`);
  process.exit(1);
}

const TYPES = {
  '.js': /^(text|application)\/javascript/,
  '.wasm': /^application\/wasm/,
  '.ttf': /^(font\/ttf|application\/octet-stream)/,
  '.otf': /^(font\/otf|application\/octet-stream)/,
};

async function checkCompressed(rel, cache) {
  const urlPath = `/nukhbaa/${rel}`;
  const bytes = fs.readFileSync(path.join(app, rel));
  const type = TYPES[path.extname(rel)];
  for (const [accept, want] of [
    ['gzip, deflate, br, zstd', 'br'],
    ['gzip, deflate', 'gzip'],
    ['identity', undefined],
  ]) {
    const res = await get(urlPath, accept);
    const label = `${urlPath} (Accept-Encoding: ${accept})`;
    expect(res.status === 200, `${label}: status ${res.status}`);
    if (res.status !== 200) continue;
    expect(res.headers['content-encoding'] === want, `${label}: content-encoding ${res.headers['content-encoding']}, expected ${want}`);
    expect(type.test(res.headers['content-type'] || ''), `${label}: content-type ${res.headers['content-type']}`);
    expect(res.headers['cache-control'] === cache, `${label}: cache-control ${res.headers['cache-control']}, expected ${cache}`);
    if (want) expect(/accept-encoding/i.test(res.headers.vary || ''), `${label}: no Vary: Accept-Encoding`);
    let same = false;
    try {
      same = decode(res).equals(bytes);
    } catch (e) {
      problems.push(`${label}: does not decode (${e.message})`);
      continue;
    }
    expect(same, `${label}: decodes to different bytes than the file`);
  }
}

async function main() {
  await waitForServer();

  const boot = fs.readFileSync(path.join(app, 'flutter_bootstrap.js'), 'utf8');
  const mainJs = (boot.match(/"mainJsPath":"(main\.dart\.[0-9a-f]{12}\.js)"/) || [])[1];
  const kit = (boot.match(/canvasKitBaseUrl: "(canvaskit-[0-9a-f]{12})\/"/) || [])[1];
  expect(Boolean(mainJs), 'flutter_bootstrap.js names no main.dart.<hash>.js');
  expect(Boolean(kit), 'flutter_bootstrap.js names no canvaskit-<revision>/');
  if (!mainJs || !kit) return;
  expect(!fs.existsSync(path.join(app, 'main.dart.js')), 'main.dart.js is still there');
  expect(!fs.existsSync(path.join(app, 'canvaskit')), 'canvaskit/ is still there');

  const compressed = [
    [mainJs, YEAR],
    ...['canvaskit.js', 'canvaskit.wasm', 'chromium/canvaskit.js', 'chromium/canvaskit.wasm'].map((f) => [`${kit}/${f}`, YEAR]),
  ];
  for (const dir of ['assets/fonts', 'assets/assets/fonts']) {
    const abs = path.join(app, dir);
    if (!fs.existsSync(abs)) continue;
    for (const f of fs.readdirSync(abs)) {
      if (/\.(ttf|otf)$/.test(f)) compressed.push([`${dir}/${f}`, MONTH]);
    }
  }
  expect(compressed.length >= 7, `only ${compressed.length} compressed files`);
  for (const [rel, cache] of compressed) {
    expect(fs.existsSync(path.join(app, `${rel}.br`)), `no ${rel}.br on disk`);
    await checkCompressed(rel, cache);
  }

  // A content-named file finalize_build.mjs leaves without a .br copy.
  const plain = fs.readdirSync(path.join(app, kit)).find((f) => f.endsWith('.wasm') && f !== 'canvaskit.wasm');
  if (plain) {
    const res = await get(`/nukhbaa/${kit}/${plain}`, 'gzip, deflate, br');
    expect(res.status === 200, `${kit}/${plain}: status ${res.status}`);
    expect(res.headers['content-encoding'] !== 'br', `${kit}/${plain}: sent as br without a .br copy`);
    expect(res.headers['cache-control'] === YEAR, `${kit}/${plain}: cache-control ${res.headers['cache-control']}`);
  }

  for (const urlPath of ['/nukhbaa/', '/nukhbaa/index.html', '/nukhbaa/flutter_bootstrap.js']) {
    const res = await get(urlPath, 'gzip, deflate, br');
    expect(res.status === 200, `${urlPath}: status ${res.status}`);
    expect(res.headers['cache-control'] === 'no-cache', `${urlPath}: cache-control ${res.headers['cache-control']}, expected no-cache`);
  }
  const served = decode(await get('/nukhbaa/flutter_bootstrap.js', 'gzip')).toString('utf8');
  expect(served === boot, 'the served flutter_bootstrap.js is not the one on disk');

  const logos = path.join(app, 'assets/assets/team_logos');
  const crest = fs.existsSync(logos) ? fs.readdirSync(logos).find((f) => f.endsWith('.png')) : undefined;
  expect(Boolean(crest), 'no team crest under assets/assets/team_logos');
  if (crest) {
    const res = await get(`/nukhbaa/assets/assets/team_logos/${crest}`, 'gzip, deflate, br');
    expect(res.status === 200, `team_logos/${crest}: status ${res.status}`);
    expect(res.headers['cache-control'] === WEEK, `team_logos/${crest}: cache-control ${res.headers['cache-control']}, expected ${WEEK}`);
  }

  const old = await get('/nukhbaa/main.dart.000000000000.js', 'gzip, deflate, br');
  expect(old.status === 404, `an old content name answered ${old.status}, expected 404`);
  const oldKit = await get(`/nukhbaa/${kit}/missing.wasm`, 'gzip, deflate, br');
  expect(oldKit.status === 404, `a missing CanvasKit file answered ${oldKit.status}, expected 404`);
  const direct = await get(`/nukhbaa/${mainJs}.br`, 'gzip, deflate, br');
  expect(direct.status === 404, `a .br name asked for directly answered ${direct.status}, expected 404`);
  const deep = await get('/nukhbaa/leaderboard/month', 'gzip, deflate, br');
  expect(deep.status === 200 && /text\/html/.test(deep.headers['content-type'] || ''), `a deep link answered ${deep.status} ${deep.headers['content-type']}`);
}

await main();
if (problems.length) {
  console.error(`check_mirror: ${problems.length} of ${checks} checks failed:`);
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log(`check_mirror: all ${checks} checks passed`);
