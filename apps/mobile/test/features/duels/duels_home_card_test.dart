/// The home page's duels card through the real `myDuelsProvider` and
/// `DuelsApi` over the auth harness's fake server: hidden when there is
/// nothing to say, a waiting challenge leads with one tap into its accept
/// sheet, and a recent result is told in one line.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/duels/duels_home_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _code = 'ABCDEFGHJKMN';
final DateTime _now = DateTime.utc(2026, 10, 6, 12);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

const Map<String, Object?> _invitation = <String, Object?>{
  'schema_version': 1,
  'id': 'c-in',
  'code': _code,
  'season_id': 's-1',
  'fixture_id': 'f-1',
  'home_team': 'Home FC',
  'away_team': 'Away FC',
  'kickoff_at': '2099-01-01T18:00:00.000Z',
  'challenger_user_id': 'rival',
  'challenger_name': 'Rival',
  'is_private': true,
  'capacity': 1,
  'accepted_count': 0,
  'state': 'open',
  'is_mine': false,
  'is_for_me': true,
};

Map<String, Object?> _duel({
  required String id,
  required String state,
  required String kickoffAt,
  String? outcome,
}) => <String, Object?>{
  'schema_version': 1,
  'id': id,
  'challenge_id': 'c-$id',
  'fixture_id': 'f-$id',
  'home_team': 'Home FC',
  'away_team': 'Away FC',
  'kickoff_at': kickoffAt,
  'accepted_at': '2026-10-01T12:00:00.000Z',
  'is_challenger': true,
  'opponent_user_id': 'rival',
  'opponent_name': 'Rival',
  'my_home_goals': 1,
  'my_away_goals': 0,
  'my_is_double': false,
  'opponent_home_goals': state == 'upcoming' ? null : 0,
  'opponent_away_goals': state == 'upcoming' ? null : 0,
  'opponent_is_double': state == 'upcoming' ? null : false,
  'state': state,
  'my_points': outcome == null ? null : 3,
  'opponent_points': outcome == null ? null : 0,
  'outcome': outcome,
};

Future<void> _pump(
  WidgetTester tester, {
  required List<Object?> challenges,
  required List<Object?> duels,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness((request) async {
    final String path = request.url.path;
    if (path == '/me/duels') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'challenges': challenges,
        'duels': duels,
      });
    }
    if (path == '/me/fixture-predictions') return _json(const <Object?>[]);
    if (path == '/duels/codes/$_code') return _json(_invitation);
    return okMe(sampleUser);
  }, seedToken: 'saved-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: Scaffold(body: DuelsHomeCard(now: _now)),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nothing to say: the card stays hidden', (tester) async {
    await _pump(
      tester,
      challenges: const <Object?>[],
      duels: <Object?>[
        _duel(
          id: 'old',
          state: 'settled',
          kickoffAt: '2026-09-01T18:00:00.000Z',
          outcome: 'won',
        ),
      ],
    );

    expect(find.byKey(const Key('home.duels')), findsNothing);
  });

  testWidgets('a waiting challenge opens its accept sheet in one tap', (
    tester,
  ) async {
    await _pump(
      tester,
      challenges: const <Object?>[_invitation],
      duels: <Object?>[
        _duel(
          id: 'up',
          state: 'upcoming',
          kickoffAt: '2099-01-01T18:00:00.000Z',
        ),
      ],
    );

    expect(find.byKey(const Key('home.duels.invitation')), findsOneWidget);
    expect(find.byKey(const Key('home.duels.running')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home.duels.accept')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('acceptDuel.sheet')), findsOneWidget);
  });

  testWidgets('a recent result is told in one line', (tester) async {
    await _pump(
      tester,
      challenges: const <Object?>[],
      duels: <Object?>[
        _duel(
          id: 'done',
          state: 'settled',
          kickoffAt: '2026-10-05T18:00:00.000Z',
          outcome: 'won',
        ),
      ],
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('home.duels.result')),
        matching: find.textContaining('Rival'),
        matchRoot: true,
      ),
      findsOneWidget,
    );
  });
}
