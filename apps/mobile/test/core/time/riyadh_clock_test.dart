/// A kickoff is entered and read on Riyadh's clock, whatever zone the
/// phone is on (audit L-12).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/time/riyadh_clock.dart';

void main() {
  test('21:00 in Riyadh is 18:00 UTC, and reads back as 21:00', () {
    final DateTime kickoff = RiyadhClock.instantOf(2026, 10, 20, 21, 0);
    expect(kickoff, DateTime.utc(2026, 10, 20, 18));
    expect(RiyadhClock.stamp(kickoff), '2026-10-20 21:00');
  });

  test('past midnight in Riyadh is still the day before in UTC', () {
    final DateTime kickoff = RiyadhClock.instantOf(2026, 11, 1, 1, 30);
    expect(kickoff, DateTime.utc(2026, 10, 31, 22, 30));
    expect(RiyadhClock.stamp(kickoff), '2026-11-01 01:30');
  });

  test('the phone\'s own time shows only when its zone is not Riyadh\'s', () {
    final DateTime kickoff = DateTime.utc(2026, 10, 20, 18);
    final DateTime local = kickoff.toLocal();
    final String? device = RiyadhClock.deviceLabel(kickoff);
    if (local.timeZoneOffset == RiyadhClock.offset) {
      expect(device, isNull);
    } else {
      String two(int n) => n.toString().padLeft(2, '0');
      expect(
        device,
        'على جهازك: ${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}',
      );
    }
  });
}
