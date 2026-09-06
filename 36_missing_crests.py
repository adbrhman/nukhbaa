#!/usr/bin/env python3
# 36_missing_crests — تنزيل شعارات الفرق الـ31 الناقصة وربطها.
# يُشغَّل بعد 35_team_logo_aliases. يحتاج اتصالًا بالشبكة.
import io, json, os, subprocess, sys, urllib.request

ROOT = os.path.expanduser('~/nukhbaa-backup-1787537565')
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
DART = os.path.join(ROOT, 'apps/mobile/lib/features/competition/team_logo_assets.dart')
ASSETS = os.path.join(ROOT, 'apps/mobile/assets/team_logos')
assert os.path.isfile(DART), 'MISSING: ' + DART
assert os.path.isdir(ASSETS), 'MISSING: ' + ASSETS

src = io.open(DART, encoding='utf-8').read()
assert '_normalizedArabicTeamLogoAliases' in src, 'RUN 35_team_logo_aliases FIRST'

# slug -> (الاسم العربي كما في football_data.teams, أسماء ESPN المرشّحة)
WANTED = {
    # الدوري الإيطالي
    'atalanta':   ('أتالانتا', ['Atalanta']),
    'bologna':    ('بولونيا', ['Bologna']),
    'cagliari':   ('كالياري', ['Cagliari']),
    'fiorentina': ('فيورنتينا', ['Fiorentina']),
    'frosinone':  ('فروزينوني', ['Frosinone']),
    'genoa':      ('جنوى', ['Genoa']),
    'lazio':      ('لاتسيو', ['Lazio']),
    'lecce':      ('ليتشي', ['Lecce']),
    'monza':      ('مونزا', ['Monza']),
    'parma':      ('بارما', ['Parma']),
    'sassuolo':   ('ساسولو', ['Sassuolo']),
    'torino':     ('تورينو', ['Torino']),
    'udinese':    ('أودينيزي', ['Udinese']),
    'venezia':    ('فينيسيا', ['Venezia']),
    # الدوري الإسباني
    'alaves':     ('ديبورتيفو ألافيس', ['Alav', 'Alaves']),
    # الدوري السعودي
    'al-hilal':    ('الهلال', ['Al Hilal', 'Al-Hilal']),
    'al-ahli':     ('الأهلي', ['Al Ahli', 'Al-Ahli']),
    'al-qadsiah':  ('القادسية', ['Qadsiah', 'Qadisiyah']),
    'al-taawoun':  ('التعاون', ['Taawoun', 'Taawon']),
    'al-ettifaq':  ('الاتفاق', ['Ettifaq', 'Ittifaq']),
    'neom':        ('نيوم', ['NEOM', 'Neom']),
    'al-hazem':    ('الحزم', ['Hazem', 'Hazm']),
    'al-fayha':    ('الفيحاء', ['Fayha', 'Feiha']),
    'al-fateh':    ('الفتح', ['Fateh']),
    'al-khaleej':  ('الخليج', ['Khaleej', 'Khaleej Saihat']),
    'al-shabab':   ('الشباب', ['Al Shabab', 'Al-Shabab']),
    'al-kholood':  ('الخلود', ['Kholood', 'Khulood']),
    'al-riyadh':   ('الرياض', ['Al Riyadh', 'Al-Riyadh']),
    'abha':        ('أبها', ['Abha']),
    'al-faisaly':  ('الفيصلي', ['Faisaly', 'Faisali']),
    'diriyah':     ('الدرعية', ['Diriyah', 'Diriyyah']),
}

LEAGUES = ['ita.1', 'ita.2', 'esp.1', 'ksa.1']
API = ('https://site.api.espn.com/apis/site/v2/sports/soccer/'
       '{}/teams?limit=100')


def fetch_json(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'nukhbaa/1.0'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode('utf-8'))


catalog = []  # (displayName, logoHref)
for lg in LEAGUES:
    try:
        data = fetch_json(API.format(lg))
    except Exception as exc:                       # noqa: BLE001
        print('WARN league %s: %s' % (lg, exc))
        continue
    for grp in data.get('sports', [{}])[0].get('leagues', []):
        for item in grp.get('teams', []):
            t = item.get('team', {})
            logos = t.get('logos') or []
            if not logos:
                continue
            name = '%s %s' % (t.get('displayName', ''), t.get('shortDisplayName', ''))
            catalog.append((name, logos[0].get('href')))
print('ESPN teams fetched: %d' % len(catalog))

downloaded, failed = [], []
for slug, (ar, needles) in sorted(WANTED.items()):
    dest = os.path.join(ASSETS, slug + '.png')
    if os.path.isfile(dest):
        downloaded.append(slug)
        continue
    href = None
    for name, url in catalog:
        low = name.lower()
        if any(n.lower() in low for n in needles):
            href = url
            break
    if href is None:
        failed.append((slug, 'no ESPN match'))
        continue
    try:
        req = urllib.request.Request(href, headers={'User-Agent': 'nukhbaa/1.0'})
        with urllib.request.urlopen(req, timeout=30) as r:
            blob = r.read()
    except Exception as exc:                       # noqa: BLE001
        failed.append((slug, str(exc)))
        continue
    if not blob.startswith(b'\x89PNG'):
        failed.append((slug, 'not a PNG'))
        continue
    with open(dest, 'wb') as f:
        f.write(blob)
    downloaded.append(slug)

print('downloaded/present: %d' % len(downloaded))
for slug, why in failed:
    print('FAILED %s — %s' % (slug, why))
if not downloaded:
    sys.exit('nothing downloaded; Dart left untouched')

# ---- ربط الشرائح المنزَّلة فقط -------------------------------------
SET_ANCHOR = "  'anderlecht',\n};"
assert src.count(SET_ANCHOR) == 1, 'SET ANCHOR DRIFT'
add_set = ''.join("  '%s',\n" % s for s in sorted(downloaded)
                  if "\n  '%s',\n" % s not in src)
src = src.replace(SET_ANCHOR, "  'anderlecht',\n" + add_set + "};", 1)

MAP_ANCHOR = "  'فايكينغ': 'viking',\n};"
assert src.count(MAP_ANCHOR) == 1, 'MAP ANCHOR DRIFT'
add_map = ''.join(
    "  '%s': '%s',\n" % (WANTED[s][0], s) for s in sorted(downloaded)
    if "'%s': '%s'," % (WANTED[s][0], s) not in src)
src = src.replace(MAP_ANCHOR, "  'فايكينغ': 'viking',\n" + add_map + "};", 1)

io.open(DART, 'w', encoding='utf-8').write(src)
print('WIRED %d slugs' % len(downloaded))

LOG = os.path.join(ROOT, 'docs/checkpoints/session-log.md')
entry = (u"\n2026-09-06 — 36_missing_crests: نُزّلت شعارات الفرق التي بقيت بلا "
         u"صورة بعد 35_team_logo_aliases (%d من %d) وأُضيفت شرائحها إلى "
         u"_monthlyLogoSlugs وأسماؤها العربية إلى _arabicTeamLogoAliases. "
         u"المصدر ESPN عبر نقطة teams لكل دوري (ita.1, ita.2, esp.1, ksa.1) "
         u"لا معرّفات مكتوبة يدويًا: المعرّف الرقمي في team_registry.dart كان "
         u"يُخمَّن ويصمت عند الخطأ، بينما المطابقة بالاسم على قائمة الدوري "
         u"تُبلّغ عن كل فريق لم تجده. الدوري الإيطالي يُقرأ من الدرجتين لأن "
         u"البذرة تخلط فرقًا هابطة (فروزينوني، مونزا، فينيسيا). لا يُربط في "
         u"Dart إلا ما نزل فعلًا وتحقّق من توقيعه كـPNG، فلا شريحة ميّتة "
         u"تُعيد null بصمت. لم يفلح: %s "
         u"— apps/mobile/lib/features/competition/team_logo_assets.dart, "
         u"apps/mobile/assets/team_logos/*.png\n") % (
    len(downloaded), len(WANTED),
    (', '.join(s for s, _ in failed) or 'لا شيء'))
with io.open(LOG, 'a', encoding='utf-8') as f:
    f.write(entry)

subprocess.check_call(['git', 'add', '-A'], cwd=ROOT)
subprocess.check_call(
    ['git', 'commit', '-m',
     '36_missing_crests: fetch and wire the remaining team crests'], cwd=ROOT)
