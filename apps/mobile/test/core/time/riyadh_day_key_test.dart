/// A match day is the Riyadh date of its kickoff, and a day opens at 00:00
/// Riyadh (21:00 UTC the evening before), whatever zone the device is in.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/time/riyadh_day_turnover.dart';

void main() {
  test('a kickoff is filed under its Riyadh date', () {
    // 23:59 Riyadh on the 9th, then 00:00 Riyadh on the 10th.
    expect(
      RiyadhDayTurnover.dayKeyOf(DateTime.utc(2026, 10, 9, 20, 59)),
      DateTime(2026, 10, 9),
    );
    expect(
      RiyadhDayTurnover.dayKeyOf(DateTime.utc(2026, 10, 9, 21)),
      DateTime(2026, 10, 10),
    );
    // A month opens on its own first day, never on the last of the one
    // before (the month starts at 21:00 UTC).
    expect(
      RiyadhDayTurnover.dayKeyOf(DateTime.utc(2026, 9, 30, 21)),
      DateTime(2026, 10),
    );
  });

  test('a day opens at 00:00 Riyadh', () {
    expect(
      RiyadhDayTurnover.opensAt(DateTime(2026, 10, 10)),
      DateTime.utc(2026, 10, 9, 21),
    );
    expect(
      RiyadhDayTurnover.opensAt(DateTime.utc(2026, 10, 10)),
      DateTime.utc(2026, 10, 9, 21),
    );
    expect(
      RiyadhDayTurnover.opensAt(
        RiyadhDayTurnover.dayKeyOf(DateTime.utc(2026, 10, 9, 23, 30)),
      ),
      DateTime.utc(2026, 10, 9, 21),
    );
  });
}
