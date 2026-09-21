import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('QuietHours.covers', () {
    // 2026-09-23 20:00 UTC is 23:00 in Riyadh.
    final riyadhEleven = DateTime.utc(2026, 9, 23, 20);

    test('23:00 local is quiet, 22:59 is not', () {
      expect(QuietHours.covers(riyadhEleven, utcOffsetMinutes: 180), isTrue);
      expect(
        QuietHours.covers(
          riyadhEleven.subtract(const Duration(minutes: 1)),
          utcOffsetMinutes: 180,
        ),
        isFalse,
      );
    });

    test('07:59 local is quiet, 08:00 is not', () {
      // 04:59 UTC and 05:00 UTC are 07:59 and 08:00 in Riyadh.
      expect(
        QuietHours.covers(
          DateTime.utc(2026, 9, 24, 4, 59),
          utcOffsetMinutes: 180,
        ),
        isTrue,
      );
      expect(
        QuietHours.covers(DateTime.utc(2026, 9, 24, 5), utcOffsetMinutes: 180),
        isFalse,
      );
    });

    test('the window follows the reader clock, not Riyadh', () {
      // 20:00 UTC: 23:00 in Riyadh, 20:00 at UTC+0, 00:00 at UTC+4.
      expect(QuietHours.covers(riyadhEleven, utcOffsetMinutes: 0), isFalse);
      expect(QuietHours.covers(riyadhEleven, utcOffsetMinutes: 240), isTrue);
    });

    test('a negative offset crosses the date line correctly', () {
      // 03:00 UTC is 22:00 the day before at UTC-5.
      expect(
        QuietHours.covers(DateTime.utc(2026, 9, 24, 3), utcOffsetMinutes: -300),
        isFalse,
      );
      // 04:00 UTC is 23:00 the day before at UTC-5.
      expect(
        QuietHours.covers(DateTime.utc(2026, 9, 24, 4), utcOffsetMinutes: -300),
        isTrue,
      );
    });

    test('an unknown clock is read on Riyadh time', () {
      expect(QuietHours.covers(riyadhEleven), isTrue);
      expect(QuietHours.covers(DateTime.utc(2026, 9, 23, 12)), isFalse);
    });
  });
}
