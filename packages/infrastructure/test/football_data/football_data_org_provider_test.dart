import 'dart:convert';

import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

Map<String, Object?> _match({
  required int id,
  required String utcDate,
  String status = 'TIMED',
  Map<String, Object?>? score,
}) => {
  'id': id,
  'utcDate': utcDate,
  'status': status,
  'homeTeam': {'id': 66, 'name': 'Manchester United FC'},
  'awayTeam': {'id': 65, 'name': 'Manchester City FC'},
  'score':
      score ??
      {
        'duration': 'REGULAR',
        'fullTime': {'home': null, 'away': null},
      },
};

void main() {
  test('a finished match carries its full-time score', () {
    final match = FootballDataOrgProvider.parseMatch(
      _match(
        id: 1,
        utcDate: '2026-09-13T15:30:00Z',
        status: 'FINISHED',
        score: {
          'duration': 'REGULAR',
          'fullTime': {'home': 0, 'away': 1},
        },
      ),
      'PL',
    )!;
    expect(match.externalId, '1');
    expect(match.leagueExternalId, 'PL');
    expect(match.homeTeamExternalId, '66');
    expect(match.status, ProviderMatchStatus.finished);
    expect((match.homeGoals, match.awayGoals), (0, 1));
  });

  test('extra time counts, the shoot-out does not', () {
    expect(
      FootballDataOrgProvider.finalScore({
        'duration': 'EXTRA_TIME',
        'fullTime': {'home': 2, 'away': 1},
      }),
      (2, 1),
    );
    expect(
      FootballDataOrgProvider.finalScore({
        'duration': 'PENALTY_SHOOTOUT',
        'fullTime': {'home': 6, 'away': 5},
        'regularTime': {'home': 1, 'away': 1},
        'extraTime': {'home': 0, 'away': 0},
        'penalties': {'home': 5, 'away': 4},
      }),
      (1, 1),
    );
    expect(
      FootballDataOrgProvider.finalScore({
        'duration': 'PENALTY_SHOOTOUT',
        'fullTime': {'home': 6, 'away': 5},
        'penalties': {'home': 5, 'away': 4},
      }),
      (1, 1),
    );
    expect(
      FootballDataOrgProvider.finalScore({
        'duration': 'PENALTY_SHOOTOUT',
        'fullTime': {'home': 1, 'away': 1},
      }),
      isNull,
    );
  });

  test('statuses map to the provider-neutral ones', () {
    ProviderMatchStatus s(String v) => FootballDataOrgProvider.statusOf(v);
    expect(s('TIMED'), ProviderMatchStatus.scheduled);
    expect(s('IN_PLAY'), ProviderMatchStatus.live);
    expect(s('PAUSED'), ProviderMatchStatus.live);
    expect(s('FINISHED'), ProviderMatchStatus.finished);
    expect(s('POSTPONED'), ProviderMatchStatus.postponed);
    expect(s('CANCELLED'), ProviderMatchStatus.cancelled);
    expect(s('SOMETHING'), ProviderMatchStatus.unknown);
  });

  test('asks for the UTC dates of a Riyadh day and keeps only that day, '
      'spacing the calls', () async {
    final seen = <Uri>[];
    final slept = <Duration>[];
    var clock = DateTime.utc(2026, 9, 17, 8);
    final provider = FootballDataOrgProvider(
      apiKey: 'k',
      now: () => clock,
      sleep: (d) async {
        slept.add(d);
        clock = clock.add(d);
      },
      httpClient: MockClient((request) async {
        seen.add(request.url);
        expect(request.headers['X-Auth-Token'], 'k');
        return http.Response(
          jsonEncode({
            'matches': [
              // 18 Sep 22:00 Riyadh -> kept for the 18th.
              _match(id: 1, utcDate: '2026-09-18T19:00:00Z'),
              // 19 Sep 00:30 Riyadh -> belongs to the 19th.
              _match(id: 2, utcDate: '2026-09-18T21:30:00Z'),
              // 18 Sep 01:00 Riyadh -> kept for the 18th.
              _match(id: 3, utcDate: '2026-09-17T22:00:00Z'),
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await provider.matchesOn(
      leagueExternalId: 'PL',
      riyadhDay: DateTime.utc(2026, 9, 18),
    );
    final ids = (result as Ok<List<ProviderMatch>>).value
        .map((m) => m.externalId)
        .toList();
    expect(ids, ['1', '3']);
    expect(seen.single.path, '/v4/competitions/PL/matches');
    expect(seen.single.queryParameters['dateFrom'], '2026-09-17');
    expect(seen.single.queryParameters['dateTo'], '2026-09-18');

    await provider.matchesOn(
      leagueExternalId: 'CL',
      riyadhDay: DateTime.utc(2026, 9, 18),
    );
    expect(slept.single, const Duration(milliseconds: 6500));
  });

  test('a 429 is reported as the quota code', () async {
    final provider = FootballDataOrgProvider(
      apiKey: 'k',
      httpClient: MockClient((_) async => http.Response('', 429)),
    );
    final result = await provider.matchesOn(
      leagueExternalId: 'PL',
      riyadhDay: DateTime.utc(2026, 9, 18),
    );
    expect(
      (result as Err<List<ProviderMatch>>).error.code,
      providerQuotaErrorCode,
    );
  });
}
