#!/usr/bin/env python3
# 35_team_logo_aliases — خريطة كاملة لأسماء الفرق العربية إلى شعاراتها المرفقة.
import io, os, subprocess, sys

ROOT = os.path.expanduser('~/nukhbaa-backup-1787537565')
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
P = os.path.join(ROOT, 'apps/mobile/lib/features/competition/team_logo_assets.dart')
assert os.path.isfile(P), 'MISSING: ' + P

src = io.open(P, encoding='utf-8').read()

START = 'final Map<String, String> _arabicTeamLogoAliases = <String, String>{'
i = src.index(START)
j = src.index('\n};\n', i) + len('\n};\n')
old_block = src[i:j]
assert "'ميلان': 'milan'," in old_block, 'ANCHOR DRIFT'

NEW_BLOCK = u"""/// أسماء الفرق كما تخزّنها `football_data.teams` (بالعربية) مقابل شريحة
/// الشعار المرفق في `assets/team_logos/`. البحث يجري أولًا بالنص كما ورد
/// ثم بصيغة مُطبَّعة عبر [_normalizeArabic]، فتُطابق فروق الهمزة والتاء
/// المربوطة والألف المقصورة دون سطر لكل صيغة.
///
/// كل قيمة هنا موجودة في [_monthlyLogoSlugs] وفي مجلد الأصول. الفرق التي
/// لا شعار مرفق لها (أغلب الدوري الإيطالي والسعودي) عمدًا خارج الخريطة:
/// تبقى على دائرة الحروف حتى تُضاف ملفاتها.
final Map<String, String> _arabicTeamLogoAliases = <String, String>{
  // الدوري الإنجليزي
  'أرسنال': 'arsenal',
  'أستون فيلا': 'aston-villa',
  'برايتون': 'brighton',
  'بورنموث': 'bournemouth',
  'برينتفورد': 'brentford',
  'تشيلسي': 'chelsea',
  'كوفنتري سيتي': 'coventry-city',
  'كريستال بالاس': 'crystal-palace',
  'إيفرتون': 'everton',
  'فولهام': 'fulham',
  'هال سيتي': 'hull-city',
  'إبسويتش تاون': 'ipswich',
  'إبسويتش': 'ipswich',
  'ليدز يونايتد': 'leeds-united',
  'ليدز': 'leeds-united',
  'ليفربول': 'liverpool',
  'مانشستر سيتي': 'manchester-city',
  'مانشستر يونايتد': 'manchester-united',
  'نيوكاسل': 'newcastle',
  'نيوكاسل يونايتد': 'newcastle',
  'نوتينغهام فورست': 'nottingham-forest',
  'نوتنغهام فورست': 'nottingham-forest',
  'سندرلاند': 'sunderland',
  'توتنهام': 'tottenham',
  // الدوري الألماني
  'بايرن ميونخ': 'bayern-munchen',
  'باير ليفركوزن': 'bayer-leverkusen',
  'بوروسيا دورتموند': 'borussia-dortmund',
  'بوروسيا مونشنغلادباخ': 'borussia-monchengladbach',
  'أوغسبورغ': 'augsburg',
  'يونيون برلين': 'union-berlin',
  'هامبورغ': 'hamburger-sv',
  'كولن': 'koln',
  'كولون': 'koln',
  'ماينز': 'mainz-05',
  'لايبزيغ': 'rb-leipzig',
  'شالكه': 'schalke-04',
  'فرايبورغ': 'freiburg',
  'بادربورن': 'paderborn',
  'آينتراخت فرانكفورت': 'eintracht-frankfurt',
  'إينتراخت فرانكفورت': 'eintracht-frankfurt',
  'إلفرسبيرغ': 'sv-elversberg',
  'فيردر بريمن': 'werder-bremen',
  'هوفنهايم': 'hoffenheim',
  'شتوتغارت': 'vfb-stuttgart',
  // الدوري الإسباني
  'ريال مدريد': 'real-madrid',
  'برشلونة': 'barcelona',
  'أتلتيكو مدريد': 'atletico-madrid',
  'أتلتيك بلباو': 'athletic-club',
  'ريال بيتيس': 'real-betis',
  'ريال سوسيداد': 'real-sociedad',
  'سيلتا فيغو': 'celta',
  'سيلتا': 'celta',
  'ديبورتيفو لاكورونيا': 'deportivo-la-coruna',
  'ديبورتيفو': 'deportivo',
  'إلتشي': 'elche',
  'إسبانيول': 'espanyol',
  'اسبانيول': 'espanyol',
  'خيتافي': 'getafe',
  'ليفانتي': 'levante',
  'ملقا': 'malaga',
  'مالاغا': 'malaga',
  'أوساسونا': 'osasuna',
  'راسينغ سانتاندير': 'racing',
  'رايو فايكانو': 'rayo-vallecano',
  'إشبيلية': 'sevilla',
  'فالنسيا': 'valencia',
  'فياريال': 'villarreal',
  // الدوري الإيطالي (المتوفّر شعارها فقط)
  'ميلان': 'milan',
  'إيه سي ميلان': 'milan',
  'يوفنتوس': 'juventus',
  'إنتر ميلان': 'inter',
  'إنتر': 'inter',
  'روما': 'roma',
  'نابولي': 'napoli',
  'كومو': 'como-1907',
  // الدوري الفرنسي
  'باريس سان جيرمان': 'paris-saint-germain',
  'مارسيليا': 'marseille',
  'مرسيليا': 'marseille',
  'ليون': 'lyon',
  'ليل': 'lille',
  'رين': 'rennes',
  'لانس': 'rc-lens',
  // الدوري السعودي (المتوفّر شعارها فقط)
  'الاتحاد': 'al-ittihad',
  'النصر': 'al-nassr',
  // دوري أبطال أوروبا والدوري الأوروبي
  'أيك أثينا': 'aek-athens',
  'أندرلخت': 'anderlecht',
  'أرارات أرمينيا': 'ararat-armenia',
  'ألكمار': 'az-alkmaar',
  'بنفيكا': 'benfica',
  'بشيكتاش': 'besiktas',
  'بودو/غليمت': 'bodo-glimt',
  'بودو غليمت': 'bodo-glimt',
  'تسيليه': 'celje',
  'سلتيك': 'celtic',
  'كلوب بروج': 'club-brugge',
  'دينامو زغرب': 'dinamo-zagreb',
  'فنربخشة': 'fenerbahce',
  'فرنكفاروش': 'ferencvaros',
  'فينورد': 'feyenoord',
  'غلطة سراي': 'galatasaray',
  'هابوعيل بئر السبع': 'hapoel-beer-sheva',
  'ياجيلونيا بياليستوك': 'jagiellonia',
  'لاسك لينز': 'lask',
  'ليخ بوزنان': 'lech-poznan',
  'ليفسكي صوفيا': 'levski',
  'ليليستروم': 'lillestrom',
  'نايميخن': 'nec-nijmegen',
  'أوفي كريت': 'ofi',
  'أولمبياكوس': 'olympiacos',
  'أومونيا نيقوسيا': 'omonoia',
  'بورتو': 'fc-porto',
  'أيندهوفن': 'psv',
  'سابا': 'sabah',
  'سالزبورغ': 'salzburg',
  'شاختار دونيتسك': 'shakhtar',
  'سلافيا براغ': 'slavia-praha',
  'سلوفان براتيسلافا': 's-bratislava',
  'سبارتا براغ': 'sparta-praha',
  'سبورتينغ لشبونة': 'sporting-cp',
  'شتورم غراتس': 'sturm-graz',
  'توريينسي': 'torreense',
  'يونيون سان جيلواز': 'union-saint-gilloise',
  'فيكتوريا بلزن': 'viktoria-plzen',
  'فايكينغ': 'viking',
};

/// نسخة مُطبَّعة من [_arabicTeamLogoAliases] تُبنى مرّة واحدة.
final Map<String, String> _normalizedArabicTeamLogoAliases = <String, String>{
  for (final MapEntry<String, String> e in _arabicTeamLogoAliases.entries)
    _normalizeArabic(e.key): e.value,
};

/// يوحّد صور الحروف التي تختلف بين مصادر الأسماء: التطويل والتشكيل
/// يُحذفان، وهمزات الألف تُردّ إلى ألف، والتاء المربوطة إلى هاء، والألف
/// المقصورة إلى ياء، والمسافات المتكرّرة إلى واحدة.
String _normalizeArabic(String value) => value
    .replaceAll(RegExp('[\\u0640\\u064B-\\u0652]'), '')
    .replaceAll(RegExp('[\\u0622\\u0623\\u0625\\u0671]'), '\\u0627')
    .replaceAll('\\u0629', '\\u0647')
    .replaceAll('\\u0649', '\\u064A')
    .replaceAll('\\u0624', '\\u0648')
    .replaceAll('\\u0626', '\\u064A')
    .replaceAll(RegExp(r'\\s+'), ' ')
    .trim();
"""

src = src[:i] + NEW_BLOCK + src[j:]

OLD_LOOKUP = """  final String? aliased = _arabicTeamLogoAliases[trimmed];
  final String slug = aliased ?? _slugifyTeamName(trimmed);"""
NEW_LOOKUP = """  final String? aliased =
      _arabicTeamLogoAliases[trimmed] ??
      _normalizedArabicTeamLogoAliases[_normalizeArabic(trimmed)];
  final String slug = aliased ?? _slugifyTeamName(trimmed);"""
assert OLD_LOOKUP in src, 'LOOKUP ANCHOR DRIFT'
src = src.replace(OLD_LOOKUP, NEW_LOOKUP, 1)

io.open(P, 'w', encoding='utf-8').write(src)
print('PATCHED', P)

LOG = os.path.join(ROOT, 'docs/checkpoints/session-log.md')
entry = (u"\n2026-09-06 — 35_team_logo_aliases: شعارات الفرق كانت تظهر لميلان "
         u"ويوفنتوس فقط وتسقط إلى دائرة الحروف لبقية الأندية. السبب أن "
         u"`football_data.teams.name` عربي بينما `_arabicTeamLogoAliases` "
         u"كانت أربعة وعشرين اسمًا فقط، و`_slugifyTeamName` تحذف كل حرف غير "
         u"لاتيني فتعيد نصًّا فارغًا لأي اسم عربي. crest_url ليس بديلًا: قيم "
         u"الدوري الإسباني ملفات SVG لا يقرأها Image.network، وقيم دوري "
         u"الأبطال والأوروبي والسعودي روابط Storage لم تُرفع ملفاتها بعد. "
         u"فصارت الخريطة تغطّي كل اسم مبذور في supabase/seed له ملف في "
         u"assets/team_logos، ومعها _normalizeArabic لتوحيد الهمزة والتاء "
         u"المربوطة والألف المقصورة فتُطابق «إسبانيول/اسبانيول» و«مارسيليا/"
         u"مرسيليا» بلا سطر لكل صيغة. باقٍ بلا شعار عمدًا: أغلب الدوري "
         u"الإيطالي (أتالانتا، لاتسيو، تورينو…) والسعودي عدا الاتحاد والنصر، "
         u"وألافيس، وباريس إف سي — ملفات ناقصة لا خطأ في الربط "
         u"— apps/mobile/lib/features/competition/team_logo_assets.dart\n")
with io.open(LOG, 'a', encoding='utf-8') as f:
    f.write(entry)
print('LOGGED')

subprocess.check_call(['git', 'add', '-A'], cwd=ROOT)
subprocess.check_call(
    ['git', 'commit', '-m',
     '35_team_logo_aliases: map every seeded Arabic team name to its bundled crest'],
    cwd=ROOT)
