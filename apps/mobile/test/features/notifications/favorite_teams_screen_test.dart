/// Widget tests for [FavoriteTeamsScreen] over the real [AuthApi],
/// [TeamsApi] and [ApiTransport], with only the socket faked
/// ([buildAuthHarness]'s `MockClient`). The page reads
/// `GET /me/favorite-teams` and `GET /teams`, writes the whole set with
/// `PUT` on each tap, and shows what the server answered.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/account_settings_screen.dart';
import 'package:mobile/features/notifications/favorite_teams_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _path = '/me/favorite-teams';
const String _a = '11111111-1111-4111-8111-111111111111';
const String _b = '22222222-2222-4222-8222-222222222222';
const String _c = '33333333-3333-4333-8333-333333333333';
const String _d = '44444444-4444-4444-8444-444444444444';

http.Response _okJson(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _team(String id, String name) => <String, Object?>{
  'schema_version': 1,
  'id': id,
  'name': name,
  'short_name': null,
  'crest_url': null,
  'league_id': null,
};

final List<Map<String, Object?>> _catalog = <Map<String, Object?>>[
  _team(_a, 'Alpha'),
  _team(_b, 'Bravo'),
  _team(_c, 'Charlie'),
  _team(_d, 'Delta'),
];

Map<String, Object?> _set(List<String> ids) => <String, Object?>{
  'schema_version': 1,
  'team_ids': ids,
};

Future<void> _pump(
  WidgetTester tester,
  AuthHarness harness,
  Widget home,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool? _checked(WidgetTester tester, String id) => tester
    .widget<CheckboxListTile>(find.byKey(Key('favoriteTeams.team.$id')))
    .value;

void main() {
  final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('choosing a team writes PUT with the whole set', (tester) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/teams') return _okJson(_catalog);
      if (request.url.path != _path) return http.Response('not found', 404);
      if (request.method == 'PUT') {
        final Map<String, Object?> sent =
            (jsonDecode(request.body) as Map<Object?, Object?>)
                .cast<String, Object?>();
        return _okJson(sent);
      }
      return _okJson(_set(const [_a]));
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness, const FavoriteTeamsScreen());
    expect(_checked(tester, _a), isTrue);

    await tester.tap(find.byKey(const Key('favoriteTeams.team.$_b')));
    await tester.pumpAndSettle();

    final puts = harness.captured
        .where((c) => c.request.method == 'PUT')
        .toList();
    expect(puts, hasLength(1));
    expect(puts.single.request.url.path, _path);
    expect(
      (jsonDecode(puts.single.request.body)
          as Map<Object?, Object?>)['team_ids'],
      [_a, _b],
    );
    expect(_checked(tester, _b), isTrue);
  });

  testWidgets('with three chosen, a fourth cannot be picked', (tester) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/teams') return _okJson(_catalog);
      if (request.url.path == _path) return _okJson(_set(const [_a, _b, _c]));
      return http.Response('not found', 404);
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness, const FavoriteTeamsScreen());

    expect(find.text(ar.favoriteTeamsLimitReached), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('favoriteTeams.team.$_d')),
          )
          .onChanged,
      isNull,
    );
  });

  testWidgets('a failed write leaves the selection and says so', (
    tester,
  ) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/teams') return _okJson(_catalog);
      if (request.url.path != _path) return http.Response('not found', 404);
      if (request.method == 'PUT') {
        return http.Response(
          jsonEncode(<String, Object?>{'code': 'db.down', 'message': 'down'}),
          503,
          headers: const {'content-type': 'application/json'},
        );
      }
      return _okJson(_set(const []));
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness, const FavoriteTeamsScreen());
    await tester.tap(find.byKey(const Key('favoriteTeams.team.$_a')));
    await tester.pumpAndSettle();

    expect(_checked(tester, _a), isFalse);
    expect(find.text(ar.notificationSettingsSaveFailed), findsOneWidget);
  });

  testWidgets('the settings page opens it', (tester) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/teams') return _okJson(_catalog);
      if (request.url.path == _path) return _okJson(_set(const []));
      return http.Response('not found', 404);
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness, const AccountSettingsScreen());
    await tester.ensureVisible(find.byKey(const Key('account.favoriteTeams')));
    await tester.tap(find.byKey(const Key('account.favoriteTeams')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('favoriteTeams.title')), findsOneWidget);
  });
}
