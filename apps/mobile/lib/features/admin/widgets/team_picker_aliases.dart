/// Bilingual lookup for the admin team picker.
///
/// The backend catalog keeps one canonical Arabic display name + UUID.
/// English (and common Arabic variants) are input aliases only; they never
/// create a second team row.
library;

const Map<String, List<String>>
kClubWorldCupTeamAliases = <String, List<String>>{
  'الأهلي المصري': <String>[
    'Al Ahly SC',
    'Al Ahly',
    'Al-Ahly',
    'Al Ahly Cairo',
    'Al Ahly FC',
  ],
  'الأهلي': <String>['Al Ahli', 'Al-Ahli', 'Al Ahli Saudi', 'Al Ahli Saudi FC'],
  'الهلال': <String>['Al Hilal', 'Al-Hilal', 'Al Hilal Saudi'],
  'العين': <String>['Al Ain', 'Al-Ain', 'Al Ain FC'],
  'أتلتيكو مدريد': <String>[
    'Atletico Madrid',
    'Atlético Madrid',
    'Atletico de Madrid',
    'Atlético de Madrid',
    'Atletico',
  ],
  'أوكلاند سيتي': <String>['Auckland City', 'Auckland City FC'],
  'بايرن ميونخ': <String>['Bayern Munich', 'Bayern Munchen', 'Bayern'],
  'بنفيكا': <String>['Benfica', 'SL Benfica'],
  'بوكا جونيورز': <String>['Boca Juniors', 'Boca'],
  'بوروسيا دورتموند': <String>['Borussia Dortmund', 'Dortmund', 'BVB'],
  'بوتافوغو': <String>['Botafogo', 'Botafogo FR'],
  'تشيلسي': <String>['Chelsea', 'Chelsea FC'],
  'الترجي الرياضي التونسي': <String>[
    'Esperance Sportive de Tunis',
    'Espérance Sportive de Tunis',
    'Esperance de Tunis',
    'Espérance de Tunis',
    'Esperance Tunis',
    'ES Tunis',
  ],
  'فلامنغو': <String>['Flamengo', 'CR Flamengo'],
  'فلومينينسي': <String>['Fluminense', 'Fluminense FC'],
  'إنتر ميامي': <String>['Inter Miami', 'Inter Miami CF'],
  'إنتر ميلان': <String>['Inter Milan', 'Internazionale', 'Inter'],
  'يوفنتوس': <String>['Juventus', 'Juventus FC'],
  'لوس أنجلوس إف سي': <String>[
    'LAFC',
    'Los Angeles FC',
    'Los Angeles Football Club',
  ],
  'ماميلودي صن داونز': <String>['Mamelodi Sundowns', 'Mamelodi Sundowns FC'],
  'مانشستر سيتي': <String>['Manchester City', 'Manchester City FC'],
  'مونتيري': <String>['Monterrey', 'CF Monterrey'],
  'باتشوكا': <String>['Pachuca', 'CF Pachuca'],
  'بالميراس': <String>['Palmeiras', 'SE Palmeiras'],
  'باريس سان جيرمان': <String>[
    'Paris Saint-Germain',
    'Paris Saint Germain',
    'PSG',
  ],
  'بورتو': <String>['Porto', 'FC Porto'],
  'ريال مدريد': <String>['Real Madrid', 'Real Madrid CF'],
  'سالزبورغ': <String>['RB Salzburg', 'Red Bull Salzburg', 'ريد بول سالزبورغ'],
  'ريفر بليت': <String>['River Plate', 'CA River Plate'],
  'سياتل ساوندرز': <String>['Seattle Sounders', 'Seattle Sounders FC'],
  'أولسان HD': <String>['Ulsan HD', 'Ulsan HD FC', 'Ulsan Hyundai'],
  'أوراوا ريد دايموندز': <String>[
    'Urawa Red Diamonds',
    'Urawa Reds',
    'Urawa Red Diamonds FC',
  ],
  'الوداد': <String>['Wydad AC', 'Wydad Casablanca', 'Wydad'],
};

String _normalizeTeamPickerText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[-_]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

bool teamPickerMatchesQuery(String query, String canonicalName) {
  final String needle = _normalizeTeamPickerText(query);
  if (needle.isEmpty) return true;
  if (_normalizeTeamPickerText(canonicalName).contains(needle)) return true;

  final List<String>? aliases = kClubWorldCupTeamAliases[canonicalName];
  if (aliases == null) return false;
  for (final String alias in aliases) {
    if (_normalizeTeamPickerText(alias).contains(needle)) return true;
  }
  return false;
}

bool teamPickerExactMatch(String input, String canonicalName) {
  final String needle = _normalizeTeamPickerText(input);
  if (needle.isEmpty) return false;
  if (needle == _normalizeTeamPickerText(canonicalName)) return true;

  final List<String>? aliases = kClubWorldCupTeamAliases[canonicalName];
  if (aliases == null) return false;
  for (final String alias in aliases) {
    if (_normalizeTeamPickerText(alias) == needle) return true;
  }
  return false;
}
