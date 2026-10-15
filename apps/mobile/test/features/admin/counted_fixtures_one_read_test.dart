/// The admin's counted fixtures in one request (batch 156), through the
/// real `CompetitionApi` and `AdminApi` over a faked socket: the played
/// fixtures of the month are counted in one read, not one request per
/// match, and a fixture nobody was scored on is left out.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/admin_providers.dart';

import '../../support/admin_harness.dart';

const String _f1 = '00000000-0156-4000-8000-0000000000f1';
const String _f2 = '00000000-0156-4000-8000-0000000000f2';
const String _f3 = '00000000-0156-4000-8000-0000000000f3';

Map<String, Object?> _item(String id, Duration fromNow) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'Test League',
      seasonLabel: '10/2026',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-1',
        fixtureId: id,
        homeTeam: 'Home Side',
        awayTeam: 'Away Side',
        kickoffAt: DateTime.now().toUtc().add(fromNow).toIso8601String(),
      ),
    ).toJson();

void main() {
  test('one read counts every played fixture; an unscored one is left '
      'out', () async {
    final AdminHarness harness = buildAdminHarness((request) async {
      if (request.url.path == '/feed/current-month-fixtures') {
        return http.Response(
          jsonEncode(<Object?>[
            _item(_f1, const Duration(days: -2)),
            _item(_f2, const Duration(hours: -3)),
            _item(_f3, const Duration(days: 1)),
          ]),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/admin/fixture-score-counts') {
        return okJsonObject(<String, Object?>{
          'schema_version': 1,
          'counts': <String, Object?>{_f1: 12},
        });
      }
      return http.Response('not found', 404);
    });
    addTearDown(harness.dispose);

    final List<AdminCountedFixture> counted = await harness.container.read(
      adminCountedFixturesProvider.future,
    );

    expect(counted.single.item.fixture.fixtureId, _f1);
    expect(counted.single.predictionsCount, 12);
    final List<Uri> reads = <Uri>[
      for (final CapturedRequest c in harness.captured)
        if (c.request.url.path == '/admin/fixture-score-counts') c.request.url,
    ];
    expect(reads, hasLength(1));
    expect(reads.single.queryParameters['fixtures']!.split(','), <String>[
      _f1,
      _f2,
    ]);
    expect(
      harness.captured.where(
        (c) => c.request.url.path.startsWith('/admin/fixtures/'),
      ),
      isEmpty,
    );
  });
}
