import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/widgets/team_picker_aliases.dart';

void main() {
  const List<(String, String)> cwcEnglishNames = <(String, String)>[
    ('Al Ahly SC', 'الأهلي المصري'),
    ('Al Hilal', 'الهلال'),
    ('Al Ain FC', 'العين'),
    ('Atlético Madrid', 'أتلتيكو مدريد'),
    ('Auckland City FC', 'أوكلاند سيتي'),
    ('Bayern Munich', 'بايرن ميونخ'),
    ('Benfica', 'بنفيكا'),
    ('Boca Juniors', 'بوكا جونيورز'),
    ('Borussia Dortmund', 'بوروسيا دورتموند'),
    ('Botafogo', 'بوتافوغو'),
    ('Chelsea', 'تشيلسي'),
    ('Esperance Sportive de Tunis', 'الترجي الرياضي التونسي'),
    ('Flamengo', 'فلامنغو'),
    ('Fluminense', 'فلومينينسي'),
    ('Inter Miami CF', 'إنتر ميامي'),
    ('Inter Milan', 'إنتر ميلان'),
    ('Juventus', 'يوفنتوس'),
    ('LAFC', 'لوس أنجلوس إف سي'),
    ('Mamelodi Sundowns', 'ماميلودي صن داونز'),
    ('Manchester City', 'مانشستر سيتي'),
    ('Monterrey', 'مونتيري'),
    ('Pachuca', 'باتشوكا'),
    ('Palmeiras', 'بالميراس'),
    ('PSG', 'باريس سان جيرمان'),
    ('FC Porto', 'بورتو'),
    ('Real Madrid', 'ريال مدريد'),
    ('RB Salzburg', 'سالزبورغ'),
    ('River Plate', 'ريفر بليت'),
    ('Seattle Sounders FC', 'سياتل ساوندرز'),
    ('Ulsan HD FC', 'أولسان HD'),
    ('Urawa Reds', 'أوراوا ريد دايموندز'),
    ('Wydad AC', 'الوداد'),
  ];

  test(
    'all 32 Club World Cup English names resolve to their canonical team',
    () {
      expect(cwcEnglishNames, hasLength(32));
      for (final (String english, String arabic) in cwcEnglishNames) {
        expect(
          teamPickerExactMatch(english, arabic),
          isTrue,
          reason: '$english should resolve to $arabic',
        );
      }
    },
  );

  test('Saudi and Egyptian Al Ahly stay separate', () {
    expect(teamPickerExactMatch('Al Ahly SC', 'الأهلي المصري'), isTrue);
    expect(teamPickerExactMatch('Al Ahli', 'الأهلي'), isTrue);
    expect(teamPickerExactMatch('Al Ahly SC', 'الأهلي'), isFalse);
    expect(teamPickerExactMatch('Al Ahli', 'الأهلي المصري'), isFalse);
  });

  test('English queries return the canonical Arabic option', () {
    expect(teamPickerMatchesQuery('Seattle', 'سياتل ساوندرز'), isTrue);
    expect(teamPickerMatchesQuery('Bayern Munich', 'بايرن ميونخ'), isTrue);
    expect(teamPickerMatchesQuery('xyz', 'ريال مدريد'), isFalse);
  });
}
