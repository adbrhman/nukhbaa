// The daily quality scorecard (script 72): each measurable standard, its
// limit, today's value and a verdict, written to the run summary.
// Node's own modules only.
//
//   node tooling/quality/scorecard.mjs \
//     --db db.json --build build.json --web results.json \
//     --plan docs/remediation-plan.md --a11y apps/mobile/test/audit/ui_audit_baseline.json \
//     --state state.json --summary "$GITHUB_STEP_SUMMARY"
//
// Inputs, each optional (a missing one is shown as "could not measure"):
//   --db     supabase/queries/quality_scorecard.sql's JSON row
//   --build  `gh run list --json conclusion,headSha` of Build Verification
//   --web    .github/web-speed/measure.mjs's results.json
//   --plan   the audit plan's status table
//   --a11y   the UI audit ratchet (contrast, tap targets, labels, text x2)
//   --state  the verdicts of the previous run; rewritten with today's
//
// The repository is public, so the summary carries rates and verdicts, never
// how many players or sessions there were.
//
// Exit 1 -- GitHub then e-mails the owner -- only when something got
// worse since the previous run: a row that passed now fails, or the web
// app's first frame is more than 20% slower. A row that already failed
// yesterday (the web speed, the open audit items) is reported, not alerted
// on every day.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// The limits. Google's where Google publishes one; the project's own,
// marked as such, where it does not.
export const LIMITS = {
  // Android vitals: no frame should take longer than 700 ms. Google
  // publishes no share of sessions, so the project allows 5%.
  frozenSessionPct: 5,
  // Slower than one refresh interval (16 ms at 60 Hz). Project limit.
  slowFramePct: 10,
  // Core Web Vitals: LCP <= 2.5 s at the 75th percentile.
  webFirstFrameMs: 2500,
  // Fewer sessions than this in 7 days is too little to judge a platform.
  minSessions: 30,
  // An alert when the web app's first frame is this much slower than the
  // previous run.
  webRegression: 1.2,
};

const ICON = { pass: '✅', fail: '❌', warn: '⚠️', na: '⚪' };

function args(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) out[argv[i].replace(/^--/, '')] = argv[i + 1];
  return out;
}

function readJson(file) {
  if (!file || !fs.existsSync(file)) return null;
  try {
    const text = fs.readFileSync(file, 'utf8').trim();
    return text ? JSON.parse(text) : null;
  } catch {
    return null;
  }
}

const pct = (n) => `${(Math.round(n * 10) / 10).toFixed(1)}%`;
const sec = (ms) => `${(ms / 1000).toFixed(1)} ث`;
const median = (xs) => {
  const s = xs.filter((x) => Number.isFinite(x)).sort((a, b) => a - b);
  if (!s.length) return null;
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

// --- each row -------------------------------------------------------------

export function buildRow(build) {
  const row = {
    id: 'build',
    name: 'سلامة الشيفرة: التحليل والاختبارات والبناء',
    standard: 'ISO/IEC/IEEE 29119',
    limit: 'آخر Build Verification على main ناجح',
  };
  const last = Array.isArray(build) ? build[0] : null;
  if (!last) return { ...row, status: 'warn', value: 'تعذّر القراءة' };
  const sha = String(last.headSha || '').slice(0, 7);
  return {
    ...row,
    status: last.conclusion === 'success' ? 'pass' : 'fail',
    value: `${last.conclusion || '?'} (${sha})`,
  };
}

export function a11yRow(baseline) {
  const row = {
    id: 'a11y',
    name: 'إمكانية الوصول (الجزء الآلي): التباين، أهداف اللمس، التسميات، النص ×2',
    standard: 'WCAG 2.2 AA',
    limit: '0 ملاحظات معروفة',
  };
  if (!baseline || typeof baseline !== 'object') return { ...row, status: 'warn', value: 'تعذّر القراءة' };
  let findings = 0;
  let screens = 0;
  for (const counts of Object.values(baseline)) {
    screens += 1;
    for (const n of Object.values(counts || {})) if (Number.isFinite(n)) findings += n;
  }
  return {
    ...row,
    status: findings === 0 ? 'pass' : 'fail',
    value: `${findings} في ${screens} شاشة/سمة`,
  };
}

export function errorsRow(db) {
  const row = {
    id: 'errors',
    name: 'أخطاء خطيرة مفتوحة (حرجة/عالية) ظهرت خلال 7 أيام',
    standard: 'ISO/IEC 25010 — الموثوقية',
    limit: '0',
  };
  if (!db || !Array.isArray(db.open_errors)) return { ...row, status: 'warn', value: 'تعذّر قراءة البيانات' };
  const total = db.open_errors.reduce((a, e) => a + Number(e.groups || 0), 0);
  const parts = db.open_errors.map((e) => `${e.severity}/${e.source}: ${e.groups}`);
  return { ...row, status: total === 0 ? 'pass' : 'fail', value: total === 0 ? '0' : `${total} (${parts.join('، ')})` };
}

function framesRows(db) {
  const frozen = {
    id: 'frozen',
    name: 'جلسات فيها تجمّد (إطار أبطأ من 700 مللي ث)',
    standard: 'Android vitals (النسبة هدف المشروع)',
    limit: `≤ ${LIMITS.frozenSessionPct}% من الجلسات`,
  };
  const slow = {
    id: 'slow',
    name: 'الإطارات البطيئة (أبطأ من تحديث الشاشة)',
    standard: 'Android vitals (النسبة هدف المشروع)',
    limit: `≤ ${LIMITS.slowFramePct}% من الإطارات`,
  };
  if (!db || !Array.isArray(db.platforms)) {
    const v = 'تعذّر قراءة البيانات';
    return [{ ...frozen, status: 'warn', value: v }, { ...slow, status: 'warn', value: v }];
  }
  const judged = db.platforms.filter((p) => Number(p.sessions) >= LIMITS.minSessions && Number(p.frames) > 0);
  if (!judged.length) {
    const v = 'بيانات قليلة هذا الأسبوع';
    return [{ ...frozen, status: 'na', value: v }, { ...slow, status: 'na', value: v }];
  }
  const fz = judged.map((p) => ({ p: p.platform, v: (100 * Number(p.frozen_sessions)) / Number(p.sessions) }));
  const sl = judged.map((p) => ({ p: p.platform, v: (100 * Number(p.slow_frames)) / Number(p.frames) }));
  const show = (xs) => xs.map((x) => `${x.p} ${pct(x.v)}`).join('، ');
  return [
    { ...frozen, status: fz.every((x) => x.v <= LIMITS.frozenSessionPct) ? 'pass' : 'fail', value: show(fz) },
    { ...slow, status: sl.every((x) => x.v <= LIMITS.slowFramePct) ? 'pass' : 'fail', value: show(sl) },
  ];
}

export function webRow(web) {
  const row = {
    id: 'web',
    name: 'ظهور تطبيق الويب لزائر جديد (هاتف متوسط، 4G بطيئة، مختبر)',
    standard: 'Core Web Vitals — LCP',
    limit: `≤ ${sec(LIMITS.webFirstFrameMs)}`,
  };
  const profile = web && Array.isArray(web.results) ? web.results.find((r) => r.profile && r.profile.id === 'mobile-4g') : null;
  const firstFrame = profile ? median(profile.runs.map((r) => r.firstFrameMs ?? r.flutterViewMs)) : null;
  if (firstFrame == null) return { ...row, status: 'warn', value: 'تعذّر القياس', firstFrameMs: null };
  const ready = web.medianReadyMs;
  return {
    ...row,
    status: firstFrame <= LIMITS.webFirstFrameMs ? 'pass' : 'fail',
    value: `أول شاشة ${sec(firstFrame)}${Number.isFinite(ready) ? `، الجاهزية ${sec(ready)}` : ''}`,
    firstFrameMs: firstFrame,
  };
}

export function securityRow(plan) {
  const row = {
    id: 'security',
    name: 'بنود التدقيق الحرجة غير المكتملة (docs/remediation-plan.md)',
    standard: 'تدقيق الأمن والجودة',
    limit: '0',
  };
  if (!plan) return { ...row, status: 'warn', value: 'تعذّر القراءة' };
  const done = /^(تم|مغلق)/;
  const open = { C: 0, M: 0, L: 0 };
  let items = 0;
  for (const line of plan.split('\n')) {
    const m = line.match(/^\|\s*([CML])-\d+\s*\|\s*([^|]+)\|/);
    if (!m) continue;
    items += 1;
    if (!done.test(m[2].trim())) open[m[1]] += 1;
  }
  if (!items) return { ...row, status: 'warn', value: 'لم يُعثر على جدول البنود' };
  return {
    ...row,
    status: open.C === 0 ? 'pass' : 'fail',
    value: `حرجة ${open.C}، وباقية: متوسطة ${open.M}، بسيطة ${open.L}`,
  };
}

function notYetRows() {
  return [
    {
      id: 'startup',
      name: 'زمن فتح التطبيق على أجهزة اللاعبين',
      standard: 'Android vitals / Core Web Vitals',
      limit: 'أندرويد < 5 ث، الويب ≤ 2.5 ث',
      status: 'na',
      value: 'يُضاف قياسه في الخطوة الثانية (APK)',
    },
    {
      id: 'native-crash',
      name: 'انهيارات أندرويد الأصلية',
      standard: 'Android vitals',
      limit: '< 1.09% من المستخدمين يومياً',
      status: 'na',
      value: 'يحتاج مفتاح Sentry API',
    },
  ];
}

// --- the card ---------------------------------------------------------------

export function scorecard(input) {
  const db = input.db && !input.db.unavailable ? input.db : null;
  return [
    buildRow(input.build),
    errorsRow(db),
    ...framesRows(db),
    webRow(input.web),
    securityRow(input.plan),
    a11yRow(input.a11y),
    ...notYetRows(),
  ];
}

// What got worse since the previous run: the reasons to alert.
export function regressions(rows, previous) {
  const out = [];
  const before = (previous && previous.rows) || {};
  for (const r of rows) {
    if (before[r.id] === 'pass' && r.status === 'fail') out.push(`${r.name}: ${r.value}`);
  }
  const web = rows.find((r) => r.id === 'web');
  const was = previous && previous.webFirstFrameMs;
  if (web && Number.isFinite(web.firstFrameMs) && Number.isFinite(was) && web.firstFrameMs > was * LIMITS.webRegression) {
    out.push(`${web.name}: ${sec(was)} ← ${sec(web.firstFrameMs)}`);
  }
  return out;
}

export function markdown(rows, alerts, when) {
  const lines = ['# بطاقة جودة نُخبة', '', `${when}  `, ''];
  const count = (s) => rows.filter((r) => r.status === s).length;
  lines.push(
    `${ICON.pass} ${count('pass')}  ${ICON.fail} ${count('fail')}  ${ICON.warn} ${count('warn')}  ${ICON.na} ${count('na')}`,
    '',
  );
  if (alerts.length) {
    lines.push('## ساء منذ التشغيل السابق', '');
    for (const a of alerts) lines.push(`- ${ICON.fail} ${a}`);
    lines.push('');
  }
  lines.push('| | البند | المعيار | الحد | اليوم |', '|---|---|---|---|---|');
  for (const r of rows) lines.push(`| ${ICON[r.status]} | ${r.name} | ${r.standard} | ${r.limit} | ${r.value} |`);
  lines.push(
    '',
    `${ICON.pass} ضمن الحد، ${ICON.fail} خارجه، ${ICON.warn} تعذّر القياس اليوم، ${ICON.na} غير مقاس بعد. ` +
      'التشغيل يفشل (ويصلك بريد) فقط حين يسوء شيء عن التشغيل السابق.',
    '',
  );
  return lines.join('\n');
}

function main() {
  const a = args(process.argv.slice(2));
  const read = (f) => (f && fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : null);
  const rows = scorecard({
    db: readJson(a.db),
    build: readJson(a.build),
    web: readJson(a.web),
    plan: read(a.plan),
    a11y: readJson(a.a11y),
  });
  const previous = readJson(a.state);
  const alerts = regressions(rows, previous);
  const md = markdown(rows, alerts, new Date().toISOString());
  if (a.summary) fs.appendFileSync(a.summary, `${md}\n`);
  if (a.state) {
    const web = rows.find((r) => r.id === 'web');
    const state = {
      at: new Date().toISOString(),
      rows: Object.fromEntries(rows.map((r) => [r.id, r.status])),
      // A run that could not measure the web keeps the last good value.
      webFirstFrameMs: Number.isFinite(web.firstFrameMs) ? web.firstFrameMs : (previous && previous.webFirstFrameMs) ?? null,
    };
    fs.writeFileSync(a.state, JSON.stringify(state, null, 2));
  }
  for (const r of rows) console.log(`${r.status.padEnd(4)} ${r.id}`);
  if (alerts.length) {
    console.log(`scorecard: ${alerts.length} worse since the previous run`);
    process.exit(1);
  }
  console.log('scorecard: nothing got worse since the previous run');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) main();
