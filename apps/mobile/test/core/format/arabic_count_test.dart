/// The count helper the admin screens print their numbers with.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/format/arabic_count.dart';

void main() {
  test('each count takes the form of the noun its number needs', () {
    const ArabicNoun players = ArabicNoun.players;
    expect(arabicCount(0, players), '0 لاعب');
    expect(arabicCount(1, players), 'لاعب واحد');
    expect(arabicCount(2, players), 'لاعبان');
    expect(arabicCount(3, players), '3 لاعبين');
    expect(arabicCount(5, players), '5 لاعبين');
    expect(arabicCount(10, players), '10 لاعبين');
    expect(arabicCount(11, players), '11 لاعبًا');
    expect(arabicCount(14, players), '14 لاعبًا');
    expect(arabicCount(99, players), '99 لاعبًا');
    expect(arabicCount(100, players), '100 لاعب');
    expect(arabicCount(101, players), '101 لاعب');
    expect(arabicCount(105, players), '105 لاعبين');
    expect(arabicCount(120, players), '120 لاعبًا');
  });

  test('the counts from the error log screenshot', () {
    expect(arabicCount(5, ArabicNoun.players), '5 لاعبين');
    expect(arabicCount(9, ArabicNoun.times), '9 مرات');
    expect(arabicCount(20, ArabicNoun.times), '20 مرة');
    expect(arabicCount(2, ArabicNoun.errors), 'خطآن');
    expect(arabicCount(3, ArabicNoun.errors), '3 أخطاء');
    expect(arabicCount(2, ArabicNoun.timesAfterVerb), 'مرتين');
  });
}
