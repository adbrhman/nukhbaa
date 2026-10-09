/// The "today" board asks the server for one Riyadh day, 00:00 to 00:00
/// Riyadh, whatever zone the device is in: the same day the matches tab
/// shows. It used to send the device's own midnight-to-midnight.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leaderboards/leaderboards_providers.dart';

import '../../support/leaderboards_harness.dart';

void main() {
  test('the day board window is 21:00 UTC to 21:00 UTC', () async {
    final harness = buildLeaderboardsHarness(
      (_) async => okJsonObject(sampleFixtureBoard.toJson()),
    );
    addTearDown(harness.dispose);

    final DayLeaderboardKey key = (seasonId: 's-1', day: DateTime(2026, 10, 9));
    final sub = harness.container.listen(
      dayFixtureLeaderboardProvider(key),
      (_, _) {},
    );
    addTearDown(sub.close);
    await harness.container.read(dayFixtureLeaderboardProvider(key).future);

    final Map<String, String> query =
        harness.captured.single.request.url.queryParameters;
    expect(DateTime.parse(query['from']!), DateTime.utc(2026, 10, 8, 21));
    expect(DateTime.parse(query['to']!), DateTime.utc(2026, 10, 9, 21));
  });
}
