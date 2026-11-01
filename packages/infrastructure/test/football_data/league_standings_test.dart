import 'dart:convert';

import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// Script 189: the league tables the daily selection scores with.
void main() {
  group('football-data.org', () {
    test('reads the TOTAL table, leader first', () {
      final rows = FootballDataOrgProvider.parseStandings({
        'standings': [
          {
            'type': 'HOME',
            'table': [
              {
                'position': 1,
                'team': {'id': 99},
              },
            ],
          },
          {
            'type': 'TOTAL',
            'table': [
              {
                'position': 2,
                'team': {'id': 81},
                'playedGames': 10,
                'points': 23,
              },
              {
                'position': 1,
                'team': {'id': 86},
                'playedGames': 10,
                'points': 25,
              },
            ],
          },
        ],
      })!;
      expect([for (final r in rows) r.teamExternalId], ['86', '81']);
      expect(rows.first.points, 25);
      expect(rows.first.played, 10);
    });

    test('a response without standings is malformed', () {
      expect(
        FootballDataOrgProvider.parseStandings({'matches': <Object?>[]}),
        isNull,
      );
    });

    test('asks the competition standings with the key', () async {
      Uri? seen;
      final provider = FootballDataOrgProvider(
        apiKey: 'k',
        sleep: (_) async {},
        httpClient: MockClient((request) async {
          seen = request.url;
          expect(request.headers['X-Auth-Token'], 'k');
          return http.Response(
            jsonEncode({
              'standings': [
                {
                  'type': 'TOTAL',
                  'table': [
                    {
                      'position': 1,
                      'team': {'id': 5},
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await provider.standingsOf(leagueRef: 'BL1', season: 2026);

      expect(seen!.path, '/v4/competitions/BL1/standings');
      final rows = (result as Ok<List<LeagueStandingRow>>).value;
      expect(rows.single.teamExternalId, '5');
    });
  });

  group('Highlightly', () {
    Map<String, Object?> row(int position, int id) => {
      'position': position,
      'team': {'id': id, 'name': 'club $id'},
      'points': 30 - position,
      'played': 9,
    };

    test('reads every group, at the top or under data', () {
      final top = HighlightlyFootballDataProvider.parseStandings({
        'groups': [
          {
            'name': 'Roshan',
            'standings': [row(2, 20), row(1, 10)],
          },
        ],
      })!;
      expect([for (final r in top) r.teamExternalId], ['10', '20']);
      expect(top.first.points, 29);

      final under = HighlightlyFootballDataProvider.parseStandings({
        'data': {
          'groups': [
            {
              'standings': [row(1, 7)],
            },
          ],
        },
      })!;
      expect(under.single.teamExternalId, '7');

      expect(
        HighlightlyFootballDataProvider.parseStandings({'data': 'x'}),
        isNull,
      );
    });

    test('asks the league and season', () async {
      Uri? seen;
      final provider = HighlightlyFootballDataProvider(
        apiKey: 'k',
        httpClient: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'standings': [row(1, 2495916)],
                },
              ],
            }),
            200,
            headers: {'x-ratelimit-requests-remaining': '80'},
          );
        }),
      );

      final result = await provider.standingsOf(
        leagueRef: '262041',
        season: 2026,
      );

      expect(seen!.path, '/standings');
      expect(seen!.queryParameters, {'leagueId': '262041', 'season': '2026'});
      expect(
        (result as Ok<List<LeagueStandingRow>>).value.single.teamExternalId,
        '2495916',
      );
      expect(provider.remainingRequests, 80);
    });

    test('keeps the last 50 requests for the results', () async {
      var sent = 0;
      final now = DateTime.utc(2026, 11, 2, 21);
      final provider = HighlightlyFootballDataProvider(
        apiKey: 'k',
        clock: () => now,
        httpClient: MockClient((request) async {
          sent++;
          return http.Response(
            jsonEncode({'data': <Object?>[]}),
            200,
            headers: {'x-ratelimit-requests-remaining': '50'},
          );
        }),
      );
      // A schedule call reports 50 left: above the schedule reserve (25),
      // at the tables' own (50).
      await provider.matchesOn(
        leagueExternalId: '262041',
        riyadhDay: DateTime.utc(2026, 11, 3),
      );
      expect(sent, 1);

      final result = await provider.standingsOf(
        leagueRef: '262041',
        season: 2026,
      );

      expect(sent, 1);
      expect(
        (result as Err<List<LeagueStandingRow>>).error.code,
        providerQuotaErrorCode,
      );
    });
  });
}
