/// The words the cup card says for how a pair was decided (NK320_02).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/h2h/h2h_cup_texts.dart';

void main() {
  // NK320_02
  test('a pair decided by the right direction says so, not the league', () {
    final String direction = h2hCupOutcomeName('direction');
    expect(direction, contains('الاتجاه الصحيح'));
    expect(direction, isNot(contains('ترتيب الدوري')));
    expect(h2hCupOutcomeName('league'), contains('ترتيب الدوري'));
  });

  test('a value the build does not know is shown as nothing', () {
    expect(h2hCupOutcomeName('unknown'), isEmpty);
    expect(h2hCupOutcomeName(null), isEmpty);
  });
}
