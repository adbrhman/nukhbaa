import 'dart:convert';

import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const String _fixture = 'f1000000-0000-0000-0000-000000000018';

Map<String, Object?> _event(
  int team,
  String time,
  String type,
  String player, {
  required String? assist,
}) => <String, Object?>{
  'team': <String, Object?>{
    'id': team,
    'logo': 'https://highlightly.net/soccer/images/teams/$team.png',
    'name': team == 97798 ? 'Paris FC' : 'Rennes FC',
  },
  'time': time,
  'type': type,
  'assist': assist,
  'player': player,
};

/// Paris FC 4-3 Rennes FC, 2026-10-18, as the probe of 2026-10-19
/// (script 117) read it: its 26 events in the provider's own order and
/// names.
final List<Map<String, Object?>> _events = <Map<String, Object?>>[
  _event(97798, '14', 'Goal', 'Maxime López', assist: 'Lassine Sinayoko'),
  _event(80778, '23', 'Yellow Card', 'Przemysław Frankowski', assist: null),
  _event(80778, '29', 'Penalty', 'Esteban Lepaul', assist: null),
  _event(80778, '32', 'Yellow Card', 'Djaoui Cissé', assist: null),
  _event(80778, '36', 'Yellow Card', 'Adrien Thomasson', assist: null),
  _event(80778, '36', 'Yellow Card', 'Anthony Rouault', assist: null),
  _event(97798, '42', 'Yellow Card', 'Samir Chergui', assist: null),
  _event(97798, '45+4', 'Goal', 'Maxime López', assist: 'Lassine Sinayoko'),
  _event(80778, '45', 'Substitution', 'Adrien Thomasson', assist: null),
  _event(80778, '45', 'Substitution', 'Ludovic Blas', assist: null),
  _event(80778, '45', 'Substitution', 'Przemysław Frankowski', assist: null),
  _event(
    80778,
    '51',
    'VAR Goal Cancelled',
    'Sebastian Szymański',
    assist: null,
  ),
  _event(80778, '62', 'Substitution', 'Djaoui Cissé', assist: null),
  _event(97798, '67', 'Yellow Card', 'Ilan Kebbal', assist: null),
  _event(97798, '70', 'Substitution', 'Pablo Pagis', assist: null),
  _event(80778, '74', 'Penalty', 'Esteban Lepaul', assist: null),
  _event(97798, '76', 'Goal', 'Lassine Sinayoko', assist: null),
  _event(97798, '79', 'Substitution', 'Hamari Traore', assist: null),
  _event(80778, '79', 'Substitution', 'Issa Soumaré', assist: null),
  _event(97798, '79', 'Substitution', 'Ilan Kebbal', assist: null),
  _event(97798, '86', 'Substitution', 'Luca Koleosho', assist: null),
  _event(97798, '86', 'Substitution', 'Samir Chergui', assist: null),
  _event(80778, '88', 'Penalty', 'Esteban Lepaul', assist: null),
  _event(97798, '90+3', 'VAR Penalty', 'Lassine Sinayoko', assist: null),
  _event(97798, '90+5', 'Yellow Card', 'Hamari Traore', assist: null),
  _event(97798, '90+7', 'Penalty', 'Lassine Sinayoko', assist: null),
];

Map<String, Object?> _match({String state = 'Finished'}) => <String, Object?>{
  'id': 1321424223,
  'date': '2026-10-18T15:15:00.000Z',
  'league': <String, Object?>{'id': 52695, 'name': 'Ligue 1'},
  'homeTeam': <String, Object?>{'id': 97798, 'name': 'Paris FC'},
  'awayTeam': <String, Object?>{'id': 80778, 'name': 'Rennes FC'},
  'state': <String, Object?>{
    'description': state,
    'score': <String, Object?>{'current': '4 - 3'},
  },
  'venue': <String, Object?>{'name': 'Stade Jean Bouin'},
  'round': 'Regular Season - 8',
  'referee': <String, Object?>{'name': 'Bastien Dechepy'},
  'events': _events,
};

HighlightlyMatchDetailsSource _source(
  List<http.Request> seen, {
  Object? body,
  int status = 200,
  String remaining = '80',
}) => HighlightlyMatchDetailsSource(
  apiKey: 'key',
  httpClient: MockClient((http.Request request) async {
    seen.add(request);
    return http.Response(
      jsonEncode(body ?? <Object?>[_match()]),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'x-ratelimit-requests-remaining': remaining,
      },
    );
  }),
  clock: () => DateTime.utc(2026, 10, 19, 3),
);

void main() {
  test('reads every goal, card and VAR decision with its minute and side, '
      'and the half-time score from the goals', () async {
    final seen = <http.Request>[];
    final read = await _source(
      seen,
    ).details(externalMatchId: '1321424223', fixtureId: _fixture);

    expect(seen.single.url.path, '/matches/1321424223');
    expect(seen.single.headers['x-rapidapi-key'], 'key');
    final details = (read as Ok<MatchDetails?>).value!;
    expect(details.found, isTrue);
    expect(details.fixtureId, _fixture);
    expect(details.externalMatchId, '1321424223');
    expect(details.events, hasLength(26));
    expect((details.halfTimeHome, details.halfTimeAway), (2, 1));
    expect(details.venue, 'Stade Jean Bouin');
    expect(details.round, 'Regular Season - 8');
    expect(details.referee, 'Bastien Dechepy');

    String line(MatchEvent e) =>
        '${e.minute} ${e.kind.wire} ${e.home ? 'home' : 'away'} ${e.player}';
    final goals = <String>[
      for (final e in details.events)
        if (e.kind.scores) line(e),
    ];
    expect(goals, <String>[
      '14 goal home Maxime López',
      '29 penalty_goal away Esteban Lepaul',
      '45+4 goal home Maxime López',
      '74 penalty_goal away Esteban Lepaul',
      '76 goal home Lassine Sinayoko',
      '88 penalty_goal away Esteban Lepaul',
      '90+7 penalty_goal home Lassine Sinayoko',
    ]);
    final cancelled = details.events.singleWhere(
      (e) => e.kind == MatchEventKind.varGoalCancelled,
    );
    expect(line(cancelled), '51 var_goal_cancelled away Sebastian Szymański');
    expect(
      details.events.where((e) => e.kind == MatchEventKind.yellowCard),
      hasLength(7),
    );
    expect(details.events.first.assist, 'Lassine Sinayoko');
    // «VAR Penalty» (a penalty given on review) changes nothing by itself.
    expect(
      details.events.singleWhere((e) => e.minute == '90+3').kind,
      MatchEventKind.other,
    );
  });

  test('a match not over yet gives no details', () async {
    final read = await _source(
      <http.Request>[],
      body: <Object?>[_match(state: 'Second half')],
    ).details(externalMatchId: '1', fixtureId: _fixture);

    expect((read as Ok<MatchDetails?>).value, isNull);
  });

  test('the half-time score is left out when an own goal falls in the first '
      'half', () {
    final details = HighlightlyMatchDetailsSource.parseDetails(
      <String, Object?>{
        ..._match(),
        'events': <Object?>[
          _event(97798, '20', 'Own Goal', 'Someone', assist: null),
        ],
      },
      fixtureId: _fixture,
      source: 'highlightly',
      fetchedAt: DateTime.utc(2026, 10, 19),
    )!;
    expect(details.events.single.kind, MatchEventKind.ownGoal);
    expect(details.halfTimeHome, isNull);
  });

  test('stops with the daily reserve left for schedules and results', () async {
    final seen = <http.Request>[];
    final source = _source(seen, remaining: '40');
    await source.details(externalMatchId: '1', fixtureId: _fixture);
    final second = await source.details(
      externalMatchId: '2',
      fixtureId: _fixture,
    );

    expect(seen, hasLength(1));
    expect((second as Err<MatchDetails?>).error.code, providerQuotaErrorCode);
  });

  test('event names map to the app kinds', () {
    MatchEventKind k(String t) => HighlightlyMatchDetailsSource.kindOf(t);
    expect(k('Goal'), MatchEventKind.goal);
    expect(k('Penalty'), MatchEventKind.penaltyGoal);
    expect(k('Own Goal'), MatchEventKind.ownGoal);
    expect(k('Missed Penalty'), MatchEventKind.missedPenalty);
    expect(k('Yellow Card'), MatchEventKind.yellowCard);
    expect(k('Red Card'), MatchEventKind.redCard);
    expect(k('VAR Goal Cancelled'), MatchEventKind.varGoalCancelled);
    expect(k('VAR Penalty'), MatchEventKind.other);
    expect(k('Substitution'), MatchEventKind.substitution);
  });
}
