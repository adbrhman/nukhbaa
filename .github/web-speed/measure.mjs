// Nukhbaa web speed check (read-only: it only opens the page like a visitor).
// Measures how long a brand-new visitor waits until the Flutter app has
// actually rendered and its data requests have settled, not just the splash.
import puppeteer, { PredefinedNetworkConditions } from 'puppeteer';
import fs from 'node:fs/promises';
import path from 'node:path';

const TARGET_URL = process.env.TARGET_URL || 'https://nukhbaa.app/nukhbaa/';
const RUNS = Math.max(1, Math.min(10, Number(process.env.RUNS) || 5));
const OUT_DIR = process.env.OUT_DIR || path.resolve('web-speed-report');
const BUDGET_MS = 2500; // PE-01 threshold (LCP <= 2.5 s)
const TIMEOUT_MS = 120_000; // give up on a single run after this
const QUIET_MS = 2_000; // no request started/finished for this long = settled

const MOBILE_UA =
  'Mozilla/5.0 (Linux; Android 11; moto g power (2022)) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

const PROFILES = [
  {
    id: 'mobile-4g',
    label: 'هاتف متوسط + شبكة 4G بطيئة (نفس إعدادات PageSpeed)',
    cpu: 4,
    net: PredefinedNetworkConditions['Slow 4G'],
  },
  {
    id: 'unthrottled',
    label: 'بلا تقييد (شبكة خوادم GitHub السريعة)',
    cpu: 1,
    net: null,
  },
];

// Runs in the page before any of its own scripts.
function installProbes() {
  const nk = (window.__nk = { firstFrame: null, flutterView: null, splashGone: null });
  window.addEventListener('flutter-first-frame', () => {
    if (nk.firstFrame === null) nk.firstFrame = performance.now();
  });
  const seen = () =>
    document.querySelector('flutter-view, flt-glass-pane, flt-scene-host, flt-semantics-host');
  new MutationObserver(() => {
    if (nk.flutterView === null && seen()) nk.flutterView = performance.now();
  }).observe(document, { childList: true, subtree: true });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  if (!s.length) return null;
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const sec = (ms) => (ms == null ? '—' : `${(ms / 1000).toFixed(1)} ث`);
const kb = (b) => (b >= 1048576 ? `${(b / 1048576).toFixed(2)} MB` : `${Math.round(b / 1024)} KB`);
const shortUrl = (u) => {
  try {
    const x = new URL(u);
    const p = x.pathname.length > 48 ? '…' + x.pathname.slice(-47) : x.pathname;
    return x.host === new URL(TARGET_URL).host ? p : `${x.host}${p}`;
  } catch {
    return u.slice(0, 60);
  }
};

async function measureOnce(browser, profile, runNo) {
  // A fresh context = empty cache, cookies and storage, like a first visit
  // in an incognito tab.
  const context = await browser.createBrowserContext();
  const page = await context.newPage();
  await page.setViewport({ width: 412, height: 823, deviceScaleFactor: 1.75, isMobile: true, hasTouch: true });
  await page.setUserAgent(MOBILE_UA);
  await page.emulateCPUThrottling(profile.cpu);
  if (profile.net) await page.emulateNetworkConditions(profile.net);
  await page.evaluateOnNewDocument(installProbes);

  const cdp = await page.createCDPSession();
  await cdp.send('Network.enable');
  const reqs = new Map();
  let lastActivity = Date.now();
  const touch = () => (lastActivity = Date.now());
  cdp.on('Network.requestWillBeSent', (e) => {
    touch();
    if (!reqs.has(e.requestId)) reqs.set(e.requestId, { url: e.request.url, type: e.type, start: e.timestamp });
  });
  cdp.on('Network.responseReceived', (e) => {
    touch();
    const r = reqs.get(e.requestId);
    if (!r) return;
    const h = Object.fromEntries(Object.entries(e.response.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
    r.status = e.response.status;
    r.mime = e.response.mimeType;
    r.encoding = h['content-encoding'] || '';
    r.cache = h['cache-control'] || '';
  });
  cdp.on('Network.dataReceived', touch);
  cdp.on('Network.loadingFinished', (e) => {
    touch();
    const r = reqs.get(e.requestId);
    if (r) {
      r.bytes = e.encodedDataLength;
      r.ms = Math.round((e.timestamp - r.start) * 1000);
    }
  });
  cdp.on('Network.loadingFailed', (e) => {
    touch();
    const r = reqs.get(e.requestId);
    if (r) r.failed = e.errorText;
  });

  const t0 = Date.now();
  let error = null;
  try {
    await page.goto(TARGET_URL, { waitUntil: 'domcontentloaded', timeout: TIMEOUT_MS });
  } catch (e) {
    error = `فشل فتح الصفحة: ${e.message}`;
  }

  let probes = {};
  let readyAt = null;
  while (!error) {
    probes = await page.evaluate(() => window.__nk || {}).catch(() => ({}));
    const rendered = probes.firstFrame ?? probes.flutterView;
    const quiet = Date.now() - lastActivity >= QUIET_MS;
    if (rendered != null && quiet) {
      readyAt = Math.max(rendered, lastActivity - t0);
      break;
    }
    if (Date.now() - t0 > TIMEOUT_MS) {
      error = rendered == null ? 'لم يظهر التطبيق خلال دقيقتين' : 'الشبكة لم تهدأ خلال دقيقتين';
      break;
    }
    await sleep(200);
  }

  const nav = await page
    .evaluate(() => {
      const n = performance.getEntriesByType('navigation')[0];
      return n ? { ttfb: n.responseStart, dcl: n.domContentLoadedEventEnd, load: n.loadEventEnd } : {};
    })
    .catch(() => ({}));

  const shot = path.join(OUT_DIR, `${profile.id}-run${runNo}.png`);
  await page.screenshot({ path: shot }).catch(() => {});
  await context.close();

  const list = [...reqs.values()];
  return {
    run: runNo,
    error,
    readyMs: readyAt == null ? null : Math.round(readyAt),
    firstFrameMs: probes.firstFrame == null ? null : Math.round(probes.firstFrame),
    flutterViewMs: probes.flutterView == null ? null : Math.round(probes.flutterView),
    ttfbMs: nav.ttfb == null ? null : Math.round(nav.ttfb),
    loadMs: nav.load ? Math.round(nav.load) : null,
    requests: list.length,
    bytes: list.reduce((a, r) => a + (r.bytes || 0), 0),
    resources: list,
    screenshot: path.basename(shot),
  };
}

function renderer(resources) {
  const urls = resources.map((r) => r.url).join(' ');
  if (/skwasm/.test(urls)) return 'skwasm (WebAssembly)';
  if (/canvaskit/.test(urls)) return 'CanvasKit';
  return 'غير معروف';
}

function report(results) {
  const lines = [];
  const main = results.find((r) => r.profile.id === 'mobile-4g');
  const mainMed = median(main.runs.filter((r) => r.readyMs != null).map((r) => r.readyMs));
  const verdict = mainMed == null ? '⚠️ تعذّر القياس' : mainMed <= BUDGET_MS ? '✅ ناجح' : '❌ فاشل';

  lines.push(`# قياس سرعة نُخبة`, '');
  lines.push(`الرابط: ${TARGET_URL}  `);
  lines.push(`الوقت: ${new Date().toISOString()}  `);
  lines.push(`عدد المرات لكل وضع: ${RUNS}، وكل مرة زائر جديد بلا ذاكرة مؤقتة.`, '');
  lines.push(`## النتيجة للبند PE-01: ${verdict}`, '');
  lines.push(
    `زمن الجاهزية الوسيط على الهاتف و4G: **${sec(mainMed)}**، والحد المطلوب ${sec(BUDGET_MS)}.`,
    '',
    '«الجاهزية» = رسم التطبيق الحقيقي (لا شاشة التحميل) ثم هدوء طلبات الشبكة. ' +
      'هذا قياس مختبري يقارب ما يراه زائر جديد، وليس بيانات مستخدمين حقيقيين.',
    ''
  );

  for (const { profile, runs } of results) {
    const ok = runs.filter((r) => r.readyMs != null);
    lines.push(`## ${profile.label}`, '');
    lines.push('| المرة | الجاهزية | أول إطار لـFlutter | أول بايت | الطلبات | الحجم المنقول | ملاحظة |');
    lines.push('|---|---|---|---|---|---|---|');
    for (const r of runs) {
      lines.push(
        `| ${r.run} | ${sec(r.readyMs)} | ${sec(r.firstFrameMs ?? r.flutterViewMs)} | ${sec(r.ttfbMs)} | ${r.requests} | ${kb(r.bytes)} | ${r.error || ''} |`
      );
    }
    const t = ok.map((r) => r.readyMs);
    lines.push('', t.length ? `الوسيط: **${sec(median(t))}**، أسرع ${sec(Math.min(...t))}، أبطأ ${sec(Math.max(...t))}.` : 'لم تنجح أي مرة.', '');
  }

  // Heaviest files from the first throttled run: this is where the wait comes from.
  const sample = main.runs.find((r) => r.resources.length) || main.runs[0];
  const heavy = [...sample.resources].filter((r) => r.bytes).sort((a, b) => b.bytes - a.bytes).slice(0, 10);
  lines.push('## أثقل الملفات (المرة الأولى على 4G)', '');
  lines.push(`محرّك الرسم: ${renderer(sample.resources)}  `);
  lines.push(`المجموع: ${sample.requests} طلباً، ${kb(sample.bytes)}.`, '');
  lines.push('| الملف | الحجم المنقول | زمن التحميل | الضغط | التخزين المؤقت |');
  lines.push('|---|---|---|---|---|');
  for (const r of heavy) {
    lines.push(
      `| \`${shortUrl(r.url)}\` | ${kb(r.bytes)} | ${sec(r.ms)} | ${r.encoding || (r.bytes > 10240 ? '❌ بلا ضغط' : '—')} | ${r.cache ? `\`${r.cache.slice(0, 40)}\`` : '—'} |`
    );
  }
  lines.push('', 'لقطات الشاشة لكل مرة في ملف النتائج المرفق بالتشغيل (web-speed-report).', '');
  return { md: lines.join('\n'), verdict, mainMed };
}

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
  });
  const results = [];
  try {
    for (const profile of PROFILES) {
      const runs = [];
      for (let i = 1; i <= RUNS; i++) {
        const r = await measureOnce(browser, profile, i);
        console.log(`[${profile.id}] run ${i}: ready=${r.readyMs}ms firstFrame=${r.firstFrameMs}ms requests=${r.requests} bytes=${r.bytes}${r.error ? ' error=' + r.error : ''}`);
        runs.push(r);
      }
      results.push({ profile, runs });
    }
  } finally {
    await browser.close();
  }

  const { md, verdict, mainMed } = report(results);
  await fs.writeFile(path.join(OUT_DIR, 'report.md'), md);
  await fs.writeFile(
    path.join(OUT_DIR, 'results.json'),
    JSON.stringify({ url: TARGET_URL, budgetMs: BUDGET_MS, medianReadyMs: mainMed, results }, null, 2)
  );
  if (process.env.GITHUB_STEP_SUMMARY) await fs.appendFile(process.env.GITHUB_STEP_SUMMARY, md + '\n');
  console.log(`\nPE-01: ${verdict} (median ${mainMed} ms, budget ${BUDGET_MS} ms)`);

  // The job only goes red when nothing could be measured at all; a slow
  // result is reported in the summary, not as a broken build.
  const anyOk = results.some((p) => p.runs.some((r) => r.readyMs != null));
  if (!anyOk) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
