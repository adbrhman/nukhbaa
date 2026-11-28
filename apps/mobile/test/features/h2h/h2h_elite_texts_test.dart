/// The words of the elite draw months (NK184): a group is "المجموعة N" from
/// November 2026, the ladder's division before it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/h2h/h2h_texts.dart';

void main() {
  group('h2hUsesEliteDraw', () {
    test('from November 2026 on, by the month and never by the clock', () {
      expect(h2hUsesEliteDraw('2026-10-01'), isFalse);
      expect(h2hUsesEliteDraw('2026-11-01'), isTrue);
      expect(h2hUsesEliteDraw('2026-12-01'), isTrue);
      expect(h2hUsesEliteDraw('2027-01-01'), isTrue);
      expect(h2hUsesEliteDraw('2025-12-01'), isFalse);
    });

    test('a month that cannot be read keeps the ladder words', () {
      expect(h2hUsesEliteDraw(''), isFalse);
      expect(h2hUsesEliteDraw('soon'), isFalse);
    });
  });

  group('h2hGroupTitle', () {
    test('the elite groups are 1 to 4, the extra ones go on from 5', () {
      expect(h2hGroupTitle('2026-11-01', 1, 0), 'المجموعة 1');
      expect(h2hGroupTitle('2026-11-01', 1, 3), 'المجموعة 4');
      expect(h2hGroupTitle('2026-11-01', 2, 0), 'المجموعة 5');
      expect(h2hGroupTitle('2026-11-01', 2, 2), 'المجموعة 7');
    });

    // NK362C: eight elite groups from December 2026, so the extra ones go on
    // from 9; the month decides, never today's date.
    test('from December the elite groups are 1 to 8, the extra ones go on '
        'from 9', () {
      expect(h2hEliteGroupCount('2026-11-01'), 4);
      expect(h2hEliteGroupCount('2026-12-01'), 8);
      expect(h2hEliteGroupCount('2027-01-01'), 8);
      expect(h2hGroupTitle('2026-12-01', 1, 0), 'المجموعة 1');
      expect(h2hGroupTitle('2026-12-01', 1, 7), 'المجموعة 8');
      expect(h2hGroupTitle('2026-12-01', 2, 0), 'المجموعة 9');
      expect(h2hGroupTitle('2026-12-01', 2, 2), 'المجموعة 11');
      expect(h2hGroupTitle('2027-01-01', 2, 0), 'المجموعة 9');
    });

    test('before November the division and the group, as always', () {
      expect(h2hGroupTitle('2026-10-01', 2, 0), 'الدرجة الثانية · المجموعة 1');
      expect(h2hGroupTitle('2026-10-01', 4, 2), 'الدرجة الرابعة · المجموعة 3');
    });
  });

  group('the cup and the report', () {
    test('the cup is said in the legend and the pill', () {
      expect(h2hCupLegend(3), 'يتأهل للكأس أول 3');
      expect(h2hInCupZone, 'يتأهل للكأس');
    });

    test('the report counts elite and extra groups from November', () {
      expect(h2hDivisionTally('2026-11-01', 1, 4), 'مجموعات النخبة: 4');
      expect(h2hDivisionTally('2026-11-01', 2, 3), 'المجموعات الإضافية: 3');
      expect(h2hDivisionTally('2026-10-01', 2, 3), 'الدرجة الثانية: 3');
    });
  });
}
