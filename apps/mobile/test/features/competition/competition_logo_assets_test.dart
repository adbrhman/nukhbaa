import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/competition_logo_assets.dart';

void main() {
  test('resolves bundled league logos by football league name', () {
    expect(
      competitionLogoAsset(null, 'الدوري الإنجليزي الممتاز'),
      'assets/league_logos/premier-league.png',
    );
    expect(
      competitionLogoAsset(null, 'الدوري الإسباني'),
      'assets/league_logos/la-liga.png',
    );
    expect(
      competitionLogoAsset(null, 'الدوري الإيطالي'),
      'assets/league_logos/serie-a.png',
    );
    expect(
      competitionLogoAsset(null, 'الدوري الألماني'),
      'assets/league_logos/bundesliga.png',
    );
    expect(
      competitionLogoAsset(null, 'الدوري الفرنسي'),
      'assets/league_logos/ligue-1.png',
    );
    expect(
      competitionLogoAsset(null, 'دوري أبطال أوروبا'),
      'assets/league_logos/champions-league.png',
    );
    expect(
      competitionLogoAsset(null, 'الدوري الأوروبي'),
      'assets/league_logos/europa-league.png',
    );
    expect(
      competitionLogoAsset(null, 'دوري روشن السعودي'),
      'assets/league_logos/saudi-pro-league.png',
    );
    expect(
      competitionLogoAsset(null, 'كأس العالم للأندية'),
      'assets/league_logos/fifa-club-world-cup.png',
    );
    expect(
      competitionLogoAsset(null, 'FIFA Club World Cup'),
      'assets/league_logos/fifa-club-world-cup.png',
    );
  });

  test('unknown or contest-only names keep the existing fallback', () {
    expect(competitionLogoAsset(null, 'شهر 9'), isNull);
    expect(competitionLogoAsset(null), isNull);
  });
}
