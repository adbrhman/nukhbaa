/// A match of a competition the list lacks is filed under its own name
/// (script 139, migration 0183): the add-match form's league list ends
/// with «دوري جديد», which adds a league (`POST /admin/leagues`) and picks
/// it; the league is continental, so both sides are picked from the whole
/// catalog. A cancelled dialog leaves the list as it was, and a name on
/// file is offered instead of added twice.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/fixture_schedule_section.dart';
import 'package:mobile/features/admin/widgets/add_league_dialog.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _league(String id, String name, {bool cont = false}) =>
    <String, Object?>{
      'schema_version': 1,
      'id': id,
      'name': name,
      'short_name': null,
      'logo_url': null,
      'is_continental': cont,
    };

Map<String, Object?> _team(String id, String name, String? league) =>
    <String, Object?>{
      'schema_version': 1,
      'id': id,
      'name': name,
      'short_name': null,
      'crest_url': null,
      'league_id': league,
    };

/// The admin's server: one month, two leagues, two clubs of a national
/// league, and the add-league route.
final class _Server {
  final List<http.Request> requests = <http.Request>[];
  final List<Map<String, Object?>> leagues = <Map<String, Object?>>[
    _league('l-spl', 'دوري روشن السعودي'),
    _league('l-drb', 'ديربيات كبرى', cont: true),
  ];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    switch (request.url.path) {
      case '/months':
        return _json(<Object?>[
          <String, Object?>{
            'id': 'm-10',
            'competition_id': 'c-1',
            'label': '10/2026',
            'start_at': '2026-09-30T21:00:00Z',
            'end_at': '2026-10-31T21:00:00Z',
          },
        ]);
      case '/leagues':
        return _json(leagues);
      case '/teams':
        return _json(<Object?>[
          _team('t-hil', 'الهلال', 'l-spl'),
          _team('t-nas', 'النصر', 'l-spl'),
        ]);
      case '/seasons/m-10/fixtures':
        return _json(const <Object?>[]);
      case '/admin/leagues':
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final Map<String, Object?> added = _league(
          'l-new',
          (body['name']! as String).trim(),
          cont: true,
        );
        leagues.add(added);
        return _json(added, 201);
    }
    return errorEnvelope(404, 'test.unrouted', request.url.path);
  }

  List<http.Request> to(String path) => <http.Request>[
    for (final http.Request r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _pump(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final AdminHarness harness = buildAdminHarness(server.handle);
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(
          body: FixtureScheduleSection(initialSeasonId: 'm-10'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const Key _field = Key('admin.fixtures.leagueField.field');

/// Opens the league list and taps the entry keyed [key].
Future<void> _pick(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(_field));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)).last);
  await tester.pumpAndSettle();
}

/// The league the form's field shows, by name.
Finder _shown(String name) =>
    find.descendant(of: find.byKey(_field), matching: find.text(name));

void main() {
  test('a name on file is found by its spelling key', () {
    final List<LeagueDto> catalog = <LeagueDto>[
      LeagueDto.fromJson(_league('l-drb', 'ديربيات كبرى', cont: true)),
    ];
    expect(sameNameLeague(' ديربيات  كبري ', catalog)?.id, 'l-drb');
    expect(sameNameLeague('كأس السوبر', catalog), isNull);
    expect(sameNameLeague('   ', catalog), isNull);
  });

  testWidgets('«دوري جديد» adds the league, picks it, and offers the whole '
      'catalog for both sides', (tester) async {
    final _Server server = _Server();
    await _pump(tester, server);

    await _pick(tester, 'admin.fixtures.leagueField.new');
    expect(find.byKey(const Key('admin.addLeague.dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('admin.addLeague.name')),
      ' كأس السوبر الأفريقي ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.addLeague.confirm')));
    await tester.pumpAndSettle();

    final http.Request added = server.to('/admin/leagues').single;
    expect(added.method, 'POST');
    expect(jsonDecode(added.body), <String, Object?>{
      'name': 'كأس السوبر الأفريقي',
    });
    expect(find.byKey(const Key('admin.addLeague.dialog')), findsNothing);
    // The list was read again and the form is on the new league.
    expect(server.to('/leagues').length, greaterThan(1));
    expect(_shown('كأس السوبر الأفريقي'), findsOneWidget);

    // A continental league: clubs of any league resolve, none blocks.
    await tester.enterText(
      find.byKey(const Key('admin.fixtures.homeTeamField')),
      'الهلال',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.fixtures.awayTeamField')),
      'النصر',
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('admin.fixtures.homeTeamUnresolved')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('admin.fixtures.awayTeamUnresolved')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancelled dialog leaves the league picked before', (
    tester,
  ) async {
    final _Server server = _Server();
    await _pump(tester, server);

    await _pick(tester, 'admin.fixtures.leagueField.l-spl');
    expect(_shown('دوري روشن السعودي'), findsOneWidget);

    await _pick(tester, 'admin.fixtures.leagueField.new');
    await tester.tap(find.byKey(const Key('admin.addLeague.cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin.addLeague.dialog')), findsNothing);
    expect(_shown('دوري روشن السعودي'), findsOneWidget);
    expect(_shown('دوري جديد'), findsNothing);
    expect(server.to('/admin/leagues'), isEmpty);
  });

  testWidgets('a league on file under the typed name is offered, not added '
      'twice', (tester) async {
    final _Server server = _Server();
    await _pump(tester, server);

    await _pick(tester, 'admin.fixtures.leagueField.new');
    await tester.enterText(
      find.byKey(const Key('admin.addLeague.name')),
      'ديربيات كبري',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin.addLeague.sameTitle')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('admin.addLeague.confirm')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('admin.addLeague.same.l-drb')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin.addLeague.dialog')), findsNothing);
    expect(_shown('ديربيات كبرى'), findsOneWidget);
    expect(server.to('/admin/leagues'), isEmpty);
  });
}
