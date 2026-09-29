/// The admin's crowning through the real section, its real providers and the
/// real `AdminApi` / `LeaderboardsApi`, over the auth harness's fake server:
/// the month's final board is drawn as the server ranked it, only a player
/// ranked first can be chosen, the picture and the prize the admin gives show
/// in the preview -- and in the real leaderboard screen, the rehearsal --
/// before anything is sent, and the crowning then the picture reach the
/// server with their values.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/champion_admin_section.dart';
import 'package:mobile/features/leaderboards/leaderboards_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

/// A 1x1 transparent PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

final class _Server {
  _Server({this.ended = true, this.unscored = 0});

  final bool ended;
  final int unscored;
  final List<http.Request> requests = <http.Request>[];
  bool crowned = false;
  bool hasPhoto = false;

  Map<String, Object?> _champion() => <String, Object?>{
    'season_id': 'm-9',
    'season_label': '09/2026',
    'user_id': 'u-1',
    'display_name': 'Ahmad',
    'points': 42,
    'exact_count': 6,
    'decided_count': 30,
    'referral_points': 2,
    'crowned_at': '2026-10-01T12:00:00.000Z',
    'celebrate_until': '2026-10-03T12:00:00.000Z',
    if (hasPhoto) 'photo_url': '/champions/m-9/photos/u-1?v=1',
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/months') {
      return _json(<Object?>[
        <String, Object?>{
          'id': 'm-9',
          'competition_id': 'c-1',
          'label': '09/2026',
          'start_at': '2026-08-31T21:00:00Z',
          'end_at': '2026-09-30T21:00:00Z',
        },
      ]);
    }
    if (path == '/admin/champions/m-9' && request.method == 'GET') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'season_id': 'm-9',
        'season_label': '09/2026',
        'ended': ended,
        'unscored_fixtures': unscored,
        'crowned': crowned ? <String>['u-1'] : <String>[],
        'candidates': <Map<String, Object?>>[
          <String, Object?>{
            'rank': 1,
            'user_id': 'u-1',
            'display_name': 'Ahmad',
            'points': 42,
            'exact_count': 6,
            'decided_count': 30,
            'referral_points': 2,
          },
          <String, Object?>{
            'rank': 2,
            'user_id': 'u-2',
            'display_name': 'Sara',
            'points': 40,
            'exact_count': 5,
            'decided_count': 30,
            'referral_points': 0,
          },
        ],
      });
    }
    if (path == '/admin/champions/m-9' && request.method == 'POST') {
      crowned = true;
      return _json(<String, Object?>{
        'schema_version': 1,
        'champions': <Object?>[_champion()],
      });
    }
    if (path == '/admin/champions/m-9/photos/u-1') {
      hasPhoto = true;
      return _json(<String, Object?>{
        'schema_version': 1,
        'champions': <Object?>[_champion()],
      });
    }
    if (path == '/me/active-seasons') {
      return _json(<Object?>[]);
    }
    if (path == '/champions') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'champions': crowned ? <Object?>[_champion()] : <Object?>[],
      });
    }
    return http.Response('not found', 404);
  }
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  ChampionPhotoPicker? pick,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ChampionAdminSection(
            pickPhoto: pick ?? () async => (bytes: _png, mime: 'image/png'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('admin.fixtures.monthField.field')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('admin.fixtures.monthField.m-9')).last);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Checkbox _box(WidgetTester tester, String userId) =>
    tester.widget<Checkbox>(find.byKey(Key('admin.champions.choose.$userId')));

/// Whether the crowning button can be pressed.
bool _crownEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(
          find.descendant(
            of: find.byKey(const Key('admin.champions.crown')),
            matching: find.byType(FilledButton),
          ),
        )
        .onPressed !=
    null;

void main() {
  testWidgets('choose, add the picture, preview, crown', (tester) async {
    final server = _Server();
    await _open(tester, server);

    // The final board as the server ranked it; only the first can be chosen.
    expect(
      find.byKey(const Key('admin.champions.candidate.u-1')),
      findsOneWidget,
    );
    expect(_box(tester, 'u-1').onChanged, isNotNull);
    expect(_box(tester, 'u-2').onChanged, isNull);
    expect(_crownEnabled(tester), isFalse);

    await tester.tap(find.byKey(const Key('admin.champions.choose.u-1')));
    await tester.pumpAndSettle();
    expect(_crownEnabled(tester), isTrue);

    // The picture stays on the device until the crowning; the preview shows
    // it already, exactly as the leaderboard will.
    await tester.tap(find.byKey(const Key('admin.champions.photo.u-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin.champions.preview')), findsOneWidget);
    expect(find.byKey(const Key('champion.backdrop.photo')), findsOneWidget);
    expect(
      find.byKey(const Key('admin.champions.spotlight.name.u-1')),
      findsOneWidget,
    );
    expect(server.requests.where((r) => r.method == 'POST'), isEmpty);

    await _scrollTo(tester, find.byKey(const Key('admin.champions.crown')));
    await tester.tap(find.byKey(const Key('admin.champions.crown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تتويج'));
    await tester.pumpAndSettle();

    final http.Request crown = server.requests.firstWhere(
      (r) => r.method == 'POST' && r.url.path == '/admin/champions/m-9',
    );
    expect(jsonDecode(crown.body), <String, Object?>{
      'user_ids': <Object?>['u-1'],
      'force': false,
    });
    final http.Request photo = server.requests.firstWhere(
      (r) => r.url.path == '/admin/champions/m-9/photos/u-1',
    );
    expect(photo.method, 'POST');
    expect(photo.headers['content-type'], startsWith('image/png'));
    expect(photo.bodyBytes, _png);
    // The crowning comes before its picture.
    expect(
      server.requests.indexOf(crown),
      lessThan(server.requests.indexOf(photo)),
    );
    expect(
      find.text('تم التتويج، والاحتفال ظاهر الآن في شاشة المتصدرين'),
      findsOneWidget,
    );

    // The month now reads as crowned, with the picture to change.
    expect(
      find.byKey(const Key('admin.champions.crownedBanner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.champions.replacePhoto.u-1')),
      findsOneWidget,
    );
  });

  testWidgets('a month with fixtures left unscored is crowned with force', (
    tester,
  ) async {
    final server = _Server(unscored: 2);
    await _open(tester, server);

    expect(find.byKey(const Key('admin.champions.unscored')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.champions.choose.u-1')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('admin.champions.crown')));
    await tester.tap(find.byKey(const Key('admin.champions.crown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تتويج'));
    await tester.pumpAndSettle();

    final http.Request crown = server.requests.firstWhere(
      (r) => r.method == 'POST' && r.url.path == '/admin/champions/m-9',
    );
    expect((jsonDecode(crown.body) as Map<String, Object?>)['force'], true);
    // No picture was picked, so none is sent.
    expect(
      server.requests.where((r) => r.url.path.contains('/photos/')),
      isEmpty,
    );
  });

  testWidgets('a month not over cannot be crowned', (tester) async {
    final server = _Server(ended: false);
    await _open(tester, server);

    expect(find.byKey(const Key('admin.champions.notOver')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.champions.choose.u-1')));
    await tester.pumpAndSettle();
    expect(_crownEnabled(tester), isFalse);
  });

  testWidgets('a picture over 512 KB is refused before sending', (
    tester,
  ) async {
    final server = _Server();
    await _open(
      tester,
      server,
      pick: () async =>
          (bytes: Uint8List(championPhotoMaxBytes + 1), mime: 'image/png'),
    );

    await tester.tap(find.byKey(const Key('admin.champions.choose.u-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.champions.photo.u-1')));
    await tester.pumpAndSettle();

    expect(find.text('الصورة أكبر من 512 ك.ب، اختر صورة أصغر'), findsOneWidget);
    expect(find.byKey(const Key('champion.backdrop.photo')), findsNothing);
  });

  testWidgets('the prize shows in the preview and goes with the crowning', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    await tester.tap(find.byKey(const Key('admin.champions.choose.u-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.champions.prize')),
      '150 ريال سعودي',
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('admin.champions.spotlight.prize.u-1')),
          )
          .data,
      contains('150 ريال سعودي'),
    );

    await _scrollTo(tester, find.byKey(const Key('admin.champions.crown')));
    await tester.tap(find.byKey(const Key('admin.champions.crown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تتويج'));
    await tester.pumpAndSettle();

    final http.Request crown = server.requests.firstWhere(
      (r) => r.method == 'POST' && r.url.path == '/admin/champions/m-9',
    );
    expect(
      (jsonDecode(crown.body) as Map<String, Object?>)['prize'],
      '150 ريال سعودي',
    );
  });

  testWidgets('the rehearsal opens the real leaderboard with the champion', (
    tester,
  ) async {
    final server = _Server(ended: false);
    await _open(tester, server);

    await tester.tap(find.byKey(const Key('admin.champions.choose.u-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.champions.photo.u-1')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('admin.champions.rehearse')));
    await tester.tap(find.byKey(const Key('admin.champions.rehearse')));
    await tester.pumpAndSettle();

    // The very screen the players open, before the month is even over:
    // nothing was sent to the server.
    expect(find.byType(LeaderboardsScreen), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('leaderboards.champion.name.u-1')))
          .data,
      'Ahmad',
    );
    expect(find.byKey(const Key('champion.backdrop.photo')), findsWidgets);
    expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  test('the picture type is read from its bytes', () {
    expect(championPhotoMime(_png), 'image/png');
    expect(
      championPhotoMime(const <int>[0xFF, 0xD8, 0xFF, 0xE0]),
      'image/jpeg',
    );
    expect(
      championPhotoMime(ascii.encode('RIFF\u0000\u0000\u0000\u0000WEBPVP8 ')),
      'image/webp',
    );
    expect(championPhotoMime(const <int>[1, 2, 3, 4]), isNull);
  });
}
