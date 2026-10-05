/// The Duels page through its real providers and the real `DuelsApi`, over
/// the auth harness's fake server: the opponent's pick stays hidden before
/// kickoff, a settled duel shows its result, a typed code opens the accept
/// sheet that sends the caller's saved prediction with its double, and the
/// challenger cancels after confirming. Also the post-save offer: once per
/// fixture, never inside the server's 30-minute window.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/duels/duel_offer.dart';
import 'package:mobile/features/duels/duels_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _challenge({
  required String id,
  required String code,
  bool isMine = false,
  bool isForMe = false,
}) => <String, Object?>{
  'schema_version': 1,
  'id': id,
  'code': code,
  'season_id': 's-1',
  'fixture_id': 'f-1',
  'home_team': 'Home FC',
  'away_team': 'Away FC',
  'kickoff_at': '2099-01-01T18:00:00.000Z',
  'challenger_user_id': isMine ? 'me' : 'rival',
  'challenger_name': isMine ? 'Me' : 'Rival',
  'is_private': isForMe,
  'capacity': isForMe ? 1 : 5,
  'accepted_count': 0,
  'state': 'open',
  'is_mine': isMine,
  'is_for_me': isForMe,
};

const Map<String, Object?> _upcoming = <String, Object?>{
  'schema_version': 1,
  'id': 'duel-up',
  'challenge_id': 'c-x',
  'fixture_id': 'f-1',
  'home_team': 'Home FC',
  'away_team': 'Away FC',
  'kickoff_at': '2099-01-01T18:00:00.000Z',
  'accepted_at': '2026-10-05T12:00:00.000Z',
  'is_challenger': true,
  'opponent_user_id': 'rival',
  'opponent_name': 'Rival',
  'my_home_goals': 2,
  'my_away_goals': 1,
  'my_is_double': false,
  'opponent_home_goals': null,
  'opponent_away_goals': null,
  'opponent_is_double': null,
  'state': 'upcoming',
  'my_points': null,
  'opponent_points': null,
  'outcome': null,
};

const Map<String, Object?> _settled = <String, Object?>{
  'schema_version': 1,
  'id': 'duel-done',
  'challenge_id': 'c-y',
  'fixture_id': 'f-2',
  'home_team': 'Home FC',
  'away_team': 'Away FC',
  'kickoff_at': '2026-10-01T18:00:00.000Z',
  'accepted_at': '2026-10-01T12:00:00.000Z',
  'is_challenger': false,
  'opponent_user_id': 'rival',
  'opponent_name': 'Rival',
  'my_home_goals': 1,
  'my_away_goals': 0,
  'my_is_double': true,
  'opponent_home_goals': 0,
  'opponent_away_goals': 0,
  'opponent_is_double': false,
  'state': 'settled',
  'my_points': 6,
  'opponent_points': 0,
  'outcome': 'won',
};

/// Answers the duel routes and records what reached them.
final class _Server {
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/me/duels') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'challenges': <Object?>[
          _challenge(id: 'c-in', code: 'INVITEDCODE2', isForMe: true),
          _challenge(id: 'c-own', code: 'MYOWNCODE234', isMine: true),
        ],
        'duels': <Object?>[_upcoming, _settled],
      });
    }
    if (path == '/me/fixture-predictions') {
      return _json(<Object?>[
        <String, Object?>{
          'schema_version': 1,
          'id': 'fp-1',
          'participant_id': 'p-1',
          'fixture_id': 'f-1',
          'submitted_at': '2026-10-05T10:00:00.000Z',
          'home_goals': 3,
          'away_goals': 2,
          'is_double': true,
        },
      ]);
    }
    if (path == '/duels/codes/ABCDEFGHJKMN') {
      return _json(_challenge(id: 'c-code', code: 'ABCDEFGHJKMN'));
    }
    if (path == '/duels/challenges/c-code/accept') {
      return _json(const <String, Object?>{
        'schema_version': 1,
        'id': 'duel-new',
        'challenge_id': 'c-code',
        'fixture_id': 'f-1',
        'accepted_at': '2026-10-05T12:00:00.000Z',
      });
    }
    if (path == '/duels/challenges/c-own/cancel') {
      return _json(const <String, Object?>{'status': 'cancelled'});
    }
    return okMe(sampleUser);
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'saved-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const DuelsScreen(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hides the opponent pick before kickoff, shows a result '
      'after', (tester) async {
    await _open(tester, _Server());

    expect(find.byKey(const Key('duels.invitation.c-in')), findsOneWidget);
    expect(find.byKey(const Key('duels.own.c-own')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('duels.duel.duel-up.opponent')),
        matching: find.textContaining('يُكشف عند الانطلاق'),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('duels.duel.duel-done.status')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('duels.screen')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('duels.duel.duel-done.status')),
        matching: find.text('فزت'),
        matchRoot: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a typed code opens the sheet that keeps the saved double', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    await tester.enterText(
      find.byKey(const Key('duels.codeField')),
      'abcdefghjkmn',
    );
    await tester.tap(find.byKey(const Key('duels.openCode')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('acceptDuel.sheet')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('acceptDuel.home.value')),
        matching: find.text('3'),
        matchRoot: true,
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('acceptDuel.accept')));
    await tester.pumpAndSettle();

    final http.Request accept = server.requests.lastWhere(
      (r) => r.url.path == '/duels/challenges/c-code/accept',
    );
    final Map<String, Object?> body =
        jsonDecode(accept.body) as Map<String, Object?>;
    expect(body['home_goals'], 3);
    expect(body['away_goals'], 2);
    expect(body['is_double'], isTrue);
    expect(find.byKey(const Key('acceptDuel.sheet')), findsNothing);
  });

  testWidgets('the challenger cancels after confirming', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await tester.tap(find.byKey(const Key('duels.cancel.c-own')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('duels.cancel.confirm')));
    await tester.pumpAndSettle();

    expect(
      server.requests.where(
        (r) => r.url.path == '/duels/challenges/c-own/cancel',
      ),
      hasLength(1),
    );
  });

  group('offerDuelAfterSave', () {
    SeasonFixtureCardDto fixture(String kickoffAt) => SeasonFixtureCardDto(
      seasonId: 's-1',
      fixtureId: 'f-9',
      homeTeam: 'Home FC',
      awayTeam: 'Away FC',
      kickoffAt: kickoffAt,
    );

    Future<void> pumpOffer(
      WidgetTester tester,
      SeasonFixtureCardDto card,
      DateTime now,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  key: const Key('save'),
                  onPressed: () => offerDuelAfterSave(
                    context: context,
                    ref: ref,
                    fixture: card,
                    now: now,
                  ),
                  child: const Text('save'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('offers once per fixture', (tester) async {
      final DateTime now = DateTime.utc(2026, 10, 5, 12);
      await pumpOffer(tester, fixture('2026-10-05T18:00:00.000Z'), now);

      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('duelOffer.f-9')), findsOneWidget);

      ScaffoldMessenger.of(
        tester.element(find.byKey(const Key('save'))),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('duelOffer.f-9')), findsNothing);
    });

    testWidgets('never inside the 30-minute window', (tester) async {
      final DateTime now = DateTime.utc(2026, 10, 5, 17, 40);
      await pumpOffer(tester, fixture('2026-10-05T18:00:00.000Z'), now);

      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('duelOffer.f-9')), findsNothing);
    });
  });
}
