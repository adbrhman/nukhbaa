/// The Riyadh day turnover: it fires a few seconds after 00:00 Riyadh (21:00
/// UTC), once more two minutes later, and on a return to the app after a
/// midnight passed; never otherwise.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/time/riyadh_day_turnover.dart';

void main() {
  test('midnight is 21:00 UTC, whatever the device zone', () {
    expect(
      RiyadhDayTurnover.nextRiyadhMidnight(DateTime.utc(2026, 9, 30, 20, 59)),
      DateTime.utc(2026, 9, 30, 21),
    );
    expect(
      RiyadhDayTurnover.nextRiyadhMidnight(DateTime.utc(2026, 9, 30, 21, 0, 1)),
      DateTime.utc(2026, 10, 1, 21),
    );
    expect(
      RiyadhDayTurnover.riyadhDayOf(DateTime.utc(2026, 9, 30, 21, 5)),
      DateTime.utc(2026, 10),
    );
  });

  testWidgets('fires after midnight Riyadh, then once more', (tester) async {
    // The clock follows the test's fake time from 23:59:50 Riyadh on the
    // 30th of September.
    final DateTime start = DateTime.utc(2026, 9, 30, 20, 59, 50);
    Duration advanced = Duration.zero;
    DateTime now() => start.add(advanced);
    int fired = 0;
    final RiyadhDayTurnover turnover = RiyadhDayTurnover(
      onTurnover: () => fired++,
      now: now,
    )..start();

    Future<void> advance(Duration by) async {
      advanced += by;
      await tester.pump(by);
    }

    await advance(const Duration(seconds: 9));
    expect(fired, 0, reason: 'still the 30th in Riyadh');

    await advance(const Duration(seconds: 7));
    expect(fired, 1, reason: 'October has begun');

    await advance(RiyadhDayTurnover.followUp);
    expect(fired, 2, reason: 'the second refresh, for a clock that ran ahead');

    await advance(const Duration(hours: 3));
    expect(fired, 2, reason: 'nothing more during the day');

    // Inside the test body: a timer still armed when the body ends fails it.
    turnover.stop();
  });

  testWidgets('a return to the app after midnight fires; the same day not', (
    tester,
  ) async {
    DateTime current = DateTime.utc(2026, 9, 30, 18);
    int fired = 0;
    final RiyadhDayTurnover turnover = RiyadhDayTurnover(
      onTurnover: () => fired++,
      now: () => current,
    )..start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(fired, 0);

    // The phone slept through midnight: no timer ran, the return catches up.
    current = DateTime.utc(2026, 10, 1, 6);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(fired, 1);

    turnover.stop();
  });
}
