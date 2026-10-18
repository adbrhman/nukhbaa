/// The club list failing to load (2026-10-19): it had failed once while the
/// server was slow and stayed failed while other screens held it, so the add
/// form read every club as «ليس في قائمة الأندية» with the add-club button
/// off and nothing to say why. The real add form over the real providers,
/// with only the HTTP answers faked ([buildAdminHarness]) and Riverpod's own
/// retries off, as when they had run out.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/fixture_schedule_section.dart';
import 'package:mobile/features/competition/teams_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

/// One month, the Roshan League and Al Nassr; `GET /teams` fails
/// [teamFailures] times before it answers.
final class _Server {
  _Server({required this.teamFailures});

  int teamFailures;
  final List<http.Request> requests = <http.Request>[];

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
            'id': 'l-spl',
            'name': 'دوري روشن السعودي',
            'short_name': 'SPL',
            'logo_url': null,
            'is_continental': false,
          },
        ]);
      case '/teams':
        if (teamFailures > 0) {
          teamFailures--;
          return errorEnvelope(503, 'db.query_timeout', 'timed out');
        }
        return _json(<Object?>[
          <String, Object?>{
            'schema_version': 1,
            'id': 't-nsr',
            'name': 'النصر',
            'short_name': null,
            'crest_url': null,
            'league_id': 'l-spl',
          },
        ]);
      case '/seasons/m-10/fixtures':
        return _json(<Object?>[]);
    }
    return errorEnvelope(404, 'test.unrouted', request.url.path);
  }

  int get teamReads => <http.Request>[
    for (final http.Request r in requests)
      if (r.url.path == '/teams') r,
  ].length;
}

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

Future<void> _pickRoshan(WidgetTester tester) async {
  final Finder field = find.byKey(
    const Key('admin.fixtures.leagueField.field'),
  );
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('admin.fixtures.leagueField.l-spl')).last,
  );
  await tester.pumpAndSettle();
}

Future<void> _typeHome(WidgetTester tester, String name) async {
  await tester.enterText(
    find.byKey(const Key('admin.fixtures.homeTeamField')),
    name,
  );
  await tester.pumpAndSettle();
  // No suggestion list left open over the hints below the field.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

/// Mounts [child] only once [show] is set, below a reader that holds the
/// club list from the start, as the matches screen does.
class _HeldThenOpened extends ConsumerWidget {
  const _HeldThenOpened({required this.show, required this.child});

  final ValueNotifier<bool> show;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(teamCatalogProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: show,
      builder: (_, bool open, _) => open ? child : const SizedBox.shrink(),
    );
  }
}

void main() {
  testWidgets('a failed club list says so and is loaded again on retry, '
      'instead of every club reading as unknown', (tester) async {
    final _Server server = _Server(teamFailures: 1);
    await _pump(
      tester,
      server,
      const FixtureScheduleSection(initialSeasonId: 'm-10'),
    );

    expect(find.byKey(const Key('admin.teamCatalog.failed')), findsOneWidget);
    await _pickRoshan(tester);
    await _typeHome(tester, 'النصر');
    // Not «ليس في قائمة الأندية»: the list is not in, the club may be.
    expect(
      find.byKey(const Key('admin.fixtures.homeTeamUnresolved')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('admin.teamCatalog.retry')));
    await tester.pumpAndSettle();

    expect(server.teamReads, 2);
    expect(find.byKey(const Key('admin.teamCatalog.failed')), findsNothing);
    expect(find.byKey(const Key('admin.teamCatalog.loading')), findsNothing);
    await _typeHome(tester, 'النصر');
    expect(
      find.byKey(const Key('admin.fixtures.homeTeamUnresolved')),
      findsNothing,
    );
  });

  testWidgets('a form opened on a list that failed elsewhere asks for it '
      'again by itself', (tester) async {
    final _Server server = _Server(teamFailures: 1);
    final ValueNotifier<bool> show = ValueNotifier<bool>(false);
    addTearDown(show.dispose);
    await _pump(
      tester,
      server,
      _HeldThenOpened(
        show: show,
        child: const FixtureScheduleSection(initialSeasonId: 'm-10'),
      ),
    );
    expect(server.teamReads, 1);

    show.value = true;
    await tester.pumpAndSettle();

    expect(server.teamReads, 2);
    expect(find.byKey(const Key('admin.teamCatalog.failed')), findsNothing);
    await _pickRoshan(tester);
    await _typeHome(tester, 'النصر');
    expect(
      find.byKey(const Key('admin.fixtures.homeTeamUnresolved')),
      findsNothing,
    );
  });

  testWidgets('a club truly missing still reads as unknown once the list is '
      'in', (tester) async {
    final _Server server = _Server(teamFailures: 0);
    await _pump(
      tester,
      server,
      const FixtureScheduleSection(initialSeasonId: 'm-10'),
    );

    expect(find.byKey(const Key('admin.teamCatalog.failed')), findsNothing);
    await _pickRoshan(tester);
    await _typeHome(tester, 'نادي غير موجود');
    expect(
      find.byKey(const Key('admin.fixtures.homeTeamUnresolved')),
      findsOneWidget,
    );
  });
}
