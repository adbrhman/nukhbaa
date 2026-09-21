import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  // Tuesday 2026-09-15 12:00 UTC is 15:00 in Riyadh.
  final noon = DateTime.utc(2026, 9, 15, 12);

  group('NotificationGate.allows', () {
    test('an opted-in reader under budget, awake, is allowed', () {
      expect(
        NotificationGate.allows(optedIn: true, now: noon, sentThisWeek: 4),
        isTrue,
      );
    });

    test('a switched-off type is refused', () {
      expect(
        NotificationGate.allows(optedIn: false, now: noon, sentThisWeek: 0),
        isFalse,
      );
    });

    test('the quiet hours on the reader clock are refused', () {
      // 12:00 UTC is 23:00 at UTC+11.
      expect(
        NotificationGate.allows(
          optedIn: true,
          now: noon,
          sentThisWeek: 0,
          utcOffsetMinutes: 660,
        ),
        isFalse,
      );
    });

    test('the budget is spent at five', () {
      expect(
        NotificationGate.allows(
          optedIn: true,
          now: noon,
          sentThisWeek: NotificationGate.weeklyBudget,
        ),
        isFalse,
      );
    });
  });

  group('dates', () {
    test('the week opens on the Riyadh Monday', () {
      expect(NotificationGate.weekStartDate(noon), '2026-09-14');
    });

    test('Sunday 22:00 UTC is already Monday in Riyadh', () {
      final late = DateTime.utc(2026, 9, 20, 22);

      expect(NotificationGate.riyadhDate(late), '2026-09-21');
      expect(NotificationGate.weekStartDate(late), '2026-09-21');
    });
  });
}
