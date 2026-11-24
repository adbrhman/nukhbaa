/// The words the cup card says for how a pair was decided (NK320_02).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/h2h/h2h_cup_texts.dart';

void main() {
  // NK320_02
  test('a pair decided by the right direction says so, not the league', () {
    final String direction = h2hCupOutcomeName('direction');
    expect(direction, contains('الاتجاه الصحيح'));
    expect(direction, isNot(contains('نقاط الشهر')));
  });

  // NK322_02
  test('a pair level even on direction says the month points decided it', () {
    final String league = h2hCupOutcomeName('league');
    expect(league, contains('الاتجاه الصحيح'));
    expect(league, contains('نقاط الشهر'));
    expect(league, isNot(contains('ترتيب الدوري')));
  });

  test('a value the build does not know is shown as nothing', () {
    expect(h2hCupOutcomeName('unknown'), isEmpty);
    expect(h2hCupOutcomeName(null), isEmpty);
  });
}
