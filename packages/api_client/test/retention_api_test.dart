import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('GET /admin/retention reads the weeks, weeks as a query', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'today': '2026-09-28',
        'weeks': [
          {
            'week_start': '2026-09-28',
            'complete': false,
            'active_users': 10,
            'active_3plus': 4,
            'league_active': 5,
            'league_active_3plus': 3,
            'league_members': 6,
            'league_returned': null,
          },
        ],
        'cohorts': [
          {
            'week_start': '2026-09-28',
            'users': 4,
            'day1': {'eligible': 0, 'retained': 0},
            'day7': {'eligible': 0, 'retained': 0},
            'day14': {'eligible': 0, 'retained': 0},
            'week4': {'eligible': 0, 'retained': 0},
          },
        ],
      }),
      token: 'jwt-abc',
    );

    final result = await AdminApi(ctx.transport).retention(weeks: 12);

    final stats = (result as Ok<AdminRetentionDto>).value;
    expect(stats.today, '2026-09-28');
    expect(stats.weeks.single.active3PlusPercent, 40);
    expect(stats.weeks.single.leagueReturned, isNull);
    expect(stats.cohorts.single.users, 4);
    expect(stats.cohorts.single.day1.percent, isNull);
    expect(ctx.captured.single.method, 'GET');
    expect(ctx.captured.single.url.path, '/admin/retention');
    expect(ctx.captured.single.url.queryParameters['weeks'], '12');
  });

  test('no weeks asked for sends no query', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'schema_version': 1, 'today': '2026-09-28'}),
    );

    await AdminApi(ctx.transport).retention();

    expect(ctx.captured.single.url.queryParameters, isEmpty);
  });
}
