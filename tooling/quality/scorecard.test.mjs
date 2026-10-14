// node --test tooling/quality/scorecard.test.mjs
// Runs scorecard.mjs the way the workflow does (a child process with files),
// on the real audit plan and UI audit baseline, and on made-up players' data.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..');
const script = path.join(here, 'scorecard.mjs');

function run(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'scorecard-'));
  const write = (name, value) => {
    if (value === undefined) return path.join(dir, `${name}-missing.json`);
    const p = path.join(dir, `${name}.json`);
    fs.writeFileSync(p, typeof value === 'string' ? value : JSON.stringify(value));
    return p;
  };
  const summary = path.join(dir, 'summary.md');
  const state = files.state === undefined ? path.join(dir, 'state.json') : write('state', files.state);
  const res = spawnSync(
    process.execPath,
    [
      script,
      '--db', write('db', files.db),
      '--build', write('build', files.build),
      '--web', write('web', files.web),
      '--plan', path.join(repo, 'docs', 'remediation-plan.md'),
      '--a11y', path.join(repo, 'apps', 'mobile', 'test', 'audit', 'ui_audit_baseline.json'),
      '--state', state,
      '--summary', summary,
    ],
    { encoding: 'utf8' },
  );
  return {
    code: res.status,
    out: res.stdout + res.stderr,
    summary: fs.existsSync(summary) ? fs.readFileSync(summary, 'utf8') : '',
    state: fs.existsSync(state) ? JSON.parse(fs.readFileSync(state, 'utf8')) : null,
  };
}

const goodDb = {
  window_days: 7,
  platforms: [
    { platform: 'android', sessions: 1234, frozen_sessions: 31, frames: 987654, slow_frames: 39506 },
    { platform: 'web', sessions: 4321, frozen_sessions: 1, frames: 765432, slow_frames: 38272 },
  ],
  open_errors: [],
};
const webResults = (ms) => ({
  medianReadyMs: ms + 1000,
  results: [{ profile: { id: 'mobile-4g' }, runs: [{ firstFrameMs: ms }, { firstFrameMs: ms + 200 }, { firstFrameMs: ms - 200 }] }],
});
const green = [{ conclusion: 'success', headSha: '924a5dbc9f86' }];

test('a first run reports every row and never alerts', () => {
  const r = run({ db: goodDb, build: green, web: webResults(19000) });
  assert.equal(r.code, 0, r.out);
  for (const id of ['build', 'errors', 'frozen', 'slow', 'web', 'security', 'a11y', 'startup', 'native-crash']) {
    assert.ok(id in r.state.rows, `state has ${id}`);
  }
  assert.equal(r.state.rows.build, 'pass');
  assert.equal(r.state.rows.frozen, 'pass');
  assert.equal(r.state.rows.web, 'fail');
  assert.equal(r.state.rows.startup, 'na');
  assert.equal(r.state.webFirstFrameMs, 19000);
  assert.match(r.summary, /بطاقة جودة نُخبة/);
  assert.match(r.summary, /android 2\.5%/);
  assert.match(r.summary, /web 5\.0%/);
  // Public repository: no session or frame counts in the summary.
  for (const n of ['1234', '4321', '987654', '765432', '39506', '38272']) {
    assert.ok(!r.summary.includes(n), `the summary must not show ${n}`);
  }
});

test('a row that passed and now fails exits 1 and names it', () => {
  const before = run({ db: goodDb, build: green, web: webResults(19000) }).state;
  const r = run({ db: goodDb, build: [{ conclusion: 'failure', headSha: 'abcdef1' }], web: webResults(19000), state: before });
  assert.equal(r.code, 1, r.out);
  assert.match(r.summary, /ساء منذ التشغيل السابق/);
  assert.match(r.summary, /سلامة الشيفرة/);
});

test('a row that already failed does not alert again', () => {
  const before = run({ db: goodDb, build: green, web: webResults(19000) }).state;
  const r = run({ db: goodDb, build: green, web: webResults(19500), state: before });
  assert.equal(r.code, 0, r.out);
});

test('the web app 20% slower than the previous run alerts', () => {
  const before = run({ db: goodDb, build: green, web: webResults(15000) }).state;
  const r = run({ db: goodDb, build: green, web: webResults(19000), state: before });
  assert.equal(r.code, 1, r.out);
});

test('a missing source is shown as not measured and keeps the last web value', () => {
  const before = run({ db: goodDb, build: green, web: webResults(19000) }).state;
  const r = run({ db: { unavailable: true }, build: undefined, web: undefined, state: before });
  assert.equal(r.code, 0, r.out);
  assert.equal(r.state.rows.errors, 'warn');
  assert.equal(r.state.rows.frozen, 'warn');
  assert.equal(r.state.rows.build, 'warn');
  assert.equal(r.state.rows.web, 'warn');
  assert.equal(r.state.webFirstFrameMs, 19000);
});

test('too few sessions is not judged', () => {
  const db = { ...goodDb, platforms: [{ platform: 'android', sessions: 5, frozen_sessions: 5, frames: 100, slow_frames: 100 }] };
  const r = run({ db, build: green, web: webResults(19000) });
  assert.equal(r.state.rows.frozen, 'na');
  assert.equal(r.state.rows.slow, 'na');
});

test('open serious errors and frozen sessions over the limit fail their rows', () => {
  const db = {
    ...goodDb,
    platforms: [{ platform: 'android', sessions: 100, frozen_sessions: 9, frames: 1000, slow_frames: 300 }],
    open_errors: [{ severity: 'critical', source: 'server', groups: 1 }],
  };
  const r = run({ db, build: green, web: webResults(19000) });
  assert.equal(r.state.rows.errors, 'fail');
  assert.equal(r.state.rows.frozen, 'fail');
  assert.equal(r.state.rows.slow, 'fail');
});

test('the audit plan in the repository is read: critical items still open', () => {
  const r = run({ db: goodDb, build: green, web: webResults(19000) });
  assert.ok(['pass', 'fail'].includes(r.state.rows.security), r.summary);
  assert.match(r.summary, /حرجة \d+، وباقية: متوسطة \d+، بسيطة \d+/);
});
