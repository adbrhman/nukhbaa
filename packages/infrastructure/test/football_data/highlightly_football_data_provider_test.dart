import 'dart:convert';

import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

Map<String, Object?> _match({
  required int id,
  required String state,
  String? score,
}) => {
  'id': id,
  'date': '2026-09-13T15:30:00.000Z',
  'league': {'id': 33973, 'name': 'Premier League'},
  'homeTeam': {'id': 28867, 'name': 'Manchester United'},
  'awayTeam': {'id': 43334, 'name': 'Manchester City'},
  'state': {
    'description': state,
    'score': {'current': score},
  },
};

void main() {
  test('parses a finished match with its final score', () {
    final match = HighlightlyFootballDataProvider.parseMatch(
      _match(id: 1, state: 'Finished', score: '0 - 1'),
    )!;
    expect(match.externalId, '1');
    expect(match.leagueExternalId, '33973');
    expect(match.homeTeamExternalId, '28867');
    expect(match.kickoffAt, DateTime.utc(2026, 9, 13, 15, 30));
    expect(match.status, ProviderMatchStatus.finished);
    expect((match.homeGoals, match.awayGoals), (0, 1));
  });

  test('extra time counts, the shoot-out does not', () {
    final match = HighlightlyFootballDataProvider.parseMatch(
      _match(id: 2, state: 'Finished after penalties', score: '1 - 1'),
    )!;
    expect(match.hasFinalScore, isTrue);
    expect((match.homeGoals, match.awayGoals), (1, 1));
  });

  test('a live score is never taken as final', () {
    final match = HighlightlyFootballDataProvider.parseMatch(
      _match(id: 3, state: 'Second half', score: '2 - 0'),
    )!;
    expect(match.status, ProviderMatchStatus.live);
    expect(match.homeGoals, isNull);
  });

  test('state descriptions map to statuses', () {
    ProviderMatchStatus s(String d) =>
        HighlightlyFootballDataProvider.statusOf(d);
    expect(s('Not started'), ProviderMatchStatus.scheduled);
    expect(s('Finished after extra time'), ProviderMatchStatus.finished);
    expect(s('Postponed'), ProviderMatchStatus.postponed);
    expect(s('Cancelled'), ProviderMatchStatus.cancelled);
    expect(s('Half time'), ProviderMatchStatus.live);
    expect(s('Something new'), ProviderMatchStatus.unknown);
  });

  test('sends the identity headers and keeps a quota reserve', () async {
    http.BaseRequest? seen;
    var remaining = '26';
    final provider = HighlightlyFootballDataProvider(
      apiKey: 'k',
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'data': [_match(id: 9, state: 'Not started')],
          }),
          200,
          headers: {
            'content-type': 'application/json',
            'x-ratelimit-requests-remaining': remaining,
          },
        );
      }),
    );

    final first = await provider.matchesOn(
      leagueExternalId: '33973',
      riyadhDay: DateTime.utc(2026, 9, 19),
    );
    expect((first as Ok<List<ProviderMatch>>).value.single.externalId, '9');
    expect(seen!.headers['x-rapidapi-key'], 'k');
    expect(seen!.headers['User-Agent'], startsWith('Nukhbaa/'));
    expect(seen!.url.queryParameters['date'], '2026-09-19');
    expect(seen!.url.queryParameters['leagueId'], '33973');

    remaining = '25';
    await provider.matchesOn(
      leagueExternalId: '33973',
      riyadhDay: DateTime.utc(2026, 9, 19),
    );
    final held = await provider.matchesOn(
      leagueExternalId: '33973',
      riyadhDay: DateTime.utc(2026, 9, 20),
    );
    expect(
      (held as Err<List<ProviderMatch>>).error.code,
      providerQuotaErrorCode,
    );
  });
}
