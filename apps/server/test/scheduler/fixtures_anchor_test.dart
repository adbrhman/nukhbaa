import 'package:server/scheduler/provider_sync_scheduler.dart';
import 'package:test/test.dart';

// Script 190: the fixtures syncs run at 00:05 and 12:05 Riyadh time.
void main() {
  test('23:00 in Riyadh: the next run is 00:05', () {
    expect(
      untilNextFixturesRun(DateTime.utc(2026, 11, 5, 20)),
      const Duration(minutes: 65),
    );
  });

  test('00:05 exactly: the next run is 12:05', () {
    expect(
      untilNextFixturesRun(DateTime.utc(2026, 11, 5, 21, 5)),
      const Duration(hours: 12),
    );
  });

  test('09:00 in Riyadh: the next run is 12:05', () {
    expect(
      untilNextFixturesRun(DateTime.utc(2026, 11, 6, 6)),
      const Duration(hours: 3, minutes: 5),
    );
  });

  test('the last day of a month runs into the first of the next', () {
    expect(
      untilNextFixturesRun(DateTime.utc(2026, 11, 30, 10)),
      const Duration(hours: 11, minutes: 5),
    );
  });
}
