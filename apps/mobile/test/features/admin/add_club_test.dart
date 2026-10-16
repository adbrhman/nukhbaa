/// A match is added and corrected with both clubs picked from the list
/// (script 91, migration 0173): a name the list does not know blocks the
/// form, the add-club dialog offers the near names first, and a club the
/// list lacks is added to it (`POST /admin/teams`) and picked. On
/// 2026-10-15 «هوفنهايم - بيشتكاش» was typed by hand beside the sync's
/// «هوفنهايم - بشكتاش», and nothing saw the same match twice.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/fixture_edit_section.dart';
import 'package:mobile/features/admin/screens/sections/fixture_schedule_section.dart';
import 'package:mobile/features/admin/widgets/add_club_dialog.dart';
import 'package:mobile/features/admin/widgets/admin_ui_kit.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _team(String id, String name, {String? league}) =>
    <String, Object?>{
      'schema_version': 1,
      'id': id,
      'name': name,
      'short_name': null,
      'crest_url': null,
      'league_id': league,
    };

TeamDto _dto(String id, String name, {String? league}) =>
    TeamDto.fromJson(_team(id, name, league: league));

/// The admin's server for these screens: one month, the Europa League
/// (continental), two clubs, and the add-club route.
final class _Server {
  _Server({this.addAnswer});

  /// The answer of `POST /admin/teams`; the club added when null.
  final http.Response? addAnswer;

  final List<http.Request> requests = <http.Request>[];
  final List<Map<String, Object?>> teams = <Map<String, Object?>>[
    _team('t-hof', 'هوفنهايم'),
    _team('t-bjk', 'بشكتاش'),
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
        return _json(<Object?>[
          <String, Object?>{
            'schema_version': 1,
            'id': 'l-uel',
            'name': 'الدوري الأوروبي',
            'short_name': 'UEL',
            'logo_url': null,
            'is_continental': true,
          },
        ]);
      case '/teams':
        return _json(teams);
      case '/seasons/m-10/fixtures':
        return _json(<Object?>[_copyJson]);
      case '/admin/teams':
        final http.Response? answer = addAnswer;
        if (answer != null) return answer;
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final Map<String, Object?> added = _team(
          't-new',
          body['name']! as String,
          league: body['league_id'] as String?,
        );
        teams.add(added);
        return _json(added, 201);
    }
    return errorEnvelope(404, 'test.unrouted', request.url.path);
  }

  List<http.Request> to(String path) => <http.Request>[
    for (final http.Request r in requests)
      if (r.url.path == path) r,
  ];
}

/// The copy typed by hand: the away side is not a club of the list.
const Map<String, Object?> _copyJson = <String, Object?>{
  'schema_version': 1,
  'season_id': 'm-10',
  'fixture_id': 'f-copy',
  'home_team': 'هوفنهايم',
  'away_team': 'بيشتكاش',
  'kickoff_at': '2026-10-15T19:00:00.000Z',
  'home_team_id': 't-hof',
  'away_team_id': null,
  'league_name': 'الدوري الأوروبي',
};

Future<void> _pump(WidgetTester tester, _Server server, Widget body) async {
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
        home: Scaffold(body: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

VoidCallback? _submit(WidgetTester tester, String key) =>
    tester.widget<AdminPrimaryButton>(find.byKey(Key(key))).onPressed;

void main() {
  group('similarClubs', () {
    final List<TeamDto> catalog = <TeamDto>[
      _dto('t-bjk', 'بشكتاش'),
      _dto('t-gal', 'غلطة سراي'),
      _dto('t-hil', 'الهلال'),
      _dto('t-hil2', 'الهلال'),
      _dto('t-alb', 'ألبانيا'),
    ];

    test('a club typed one or two letters off is offered', () {
      expect(
        <String>[
          for (final TeamDto t in similarClubs('بيشتكاش', catalog)) t.id,
        ],
        <String>['t-bjk'],
      );
      expect(
        <String>[
          for (final TeamDto t in similarClubs('غلطه سراى', catalog)) t.id,
        ],
        <String>['t-gal'],
      );
    });

    test('a new name offers nothing, and one name is offered once', () {
      expect(similarClubs('نادي جديد', catalog), isEmpty);
      expect(similarClubs('الهلال', catalog), hasLength(1));
    });

    test('a continental league files a new club under none', () {
      expect(
        clubLeagueIdFor(
          const LeagueDto(
            id: 'l-uel',
            name: 'الدوري الأوروبي',
            shortName: 'UEL',
            logoUrl: null,
            isContinental: true,
          ),
        ),
        isNull,
      );
      expect(
        clubLeagueIdFor(
          const LeagueDto(
            id: 'l-spl',
            name: 'دوري روشن',
            shortName: 'SPL',
            logoUrl: null,
          ),
        ),
        'l-spl',
      );
    });
  });

  testWidgets('a side the list does not know blocks the correction until '
      'the near name is picked', (tester) async {
    final _Server server = _Server();
    await _pump(
      tester,
      server,
      FixtureEditSection(
        initialSeasonId: 'm-10',
        initialFixture: SeasonFixtureCardDto.fromJson(_copyJson),
      ),
    );

    expect(
      find.byKey(const Key('admin.fixtureEdit.awayTeamUnresolved')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.fixtureEdit.homeTeamUnresolved')),
      findsNothing,
    );
    expect(_submit(tester, 'admin.fixtureEdit.submit'), isNull);

    await _tap(
      tester,
      find.byKey(const Key('admin.fixtureEdit.awayTeamAddClub')),
    );
    expect(find.byKey(const Key('admin.addClub.dialog')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('admin.addClub.near.t-bjk')));

    expect(find.byKey(const Key('admin.addClub.dialog')), findsNothing);
    expect(_fieldText(tester, 'admin.fixtureEdit.awayTeamField'), 'بشكتاش');
    expect(
      find.byKey(const Key('admin.fixtureEdit.awayTeamUnresolved')),
      findsNothing,
    );
    expect(_submit(tester, 'admin.fixtureEdit.submit'), isNotNull);
    expect(server.to('/admin/teams'), isEmpty);
  });

  testWidgets('a club the list lacks is added to it and picked', (
    tester,
  ) async {
    final _Server server = _Server();
    await _pump(
      tester,
      server,
      const FixtureScheduleSection(initialSeasonId: 'm-10'),
    );

    await _tap(
      tester,
      find.byKey(const Key('admin.fixtures.leagueField.field')),
    );
    await tester.tap(
      find.byKey(const Key('admin.fixtures.leagueField.l-uel')).last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.fixtures.homeTeamField')),
      'هوفنهايم',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.fixtures.awayTeamField')),
      'نادي جديد',
    );
    await tester.pumpAndSettle();
    // No suggestion list left open over the buttons below the fields.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('admin.fixtures.homeTeamUnresolved')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('admin.fixtures.awayTeamUnresolved')),
      findsOneWidget,
    );
    final int catalogReads = server.to('/teams').length;
    // The switch sits on the card in a Material of its own: no assertion.
    expect(tester.takeException(), isNull);

    await _tap(tester, find.byKey(const Key('admin.fixtures.awayTeamAddClub')));
    expect(find.byKey(const Key('admin.addClub.nearTitle')), findsNothing);
    await _tap(tester, find.byKey(const Key('admin.addClub.confirm')));

    final http.Request added = server.to('/admin/teams').single;
    expect(added.method, 'POST');
    final body = jsonDecode(added.body) as Map<String, Object?>;
    expect(body['name'], 'نادي جديد');
    // The Europa League draws its clubs from other leagues: none.
    expect(body['league_id'], isNull);
    expect(find.byKey(const Key('admin.addClub.dialog')), findsNothing);
    expect(_fieldText(tester, 'admin.fixtures.awayTeamField'), 'نادي جديد');
    expect(
      find.byKey(const Key('admin.fixtures.awayTeamUnresolved')),
      findsNothing,
    );
    expect(server.to('/teams').length, greaterThan(catalogReads));
  });

  testWidgets('a club already on file is refused in the dialog, by its '
      'name', (tester) async {
    final _Server server = _Server(
      addAnswer: errorEnvelope(
        409,
        'football_data.team_exists',
        'النادي «بشكتاش» في القائمة من قبل، فاختره منها. لم يُضَف مرة ثانية.',
      ),
    );
    await _pump(
      tester,
      server,
      FixtureEditSection(
        initialSeasonId: 'm-10',
        initialFixture: SeasonFixtureCardDto.fromJson(_copyJson),
      ),
    );

    await _tap(
      tester,
      find.byKey(const Key('admin.fixtureEdit.awayTeamAddClub')),
    );
    await _tap(tester, find.byKey(const Key('admin.addClub.confirm')));

    expect(find.byKey(const Key('admin.addClub.dialog')), findsOneWidget);
    expect(find.byKey(const Key('admin.addClub.error')), findsOneWidget);
    expect(find.textContaining('«بشكتاش»'), findsOneWidget);
    expect(_submit(tester, 'admin.fixtureEdit.submit'), isNull);
  });
}
