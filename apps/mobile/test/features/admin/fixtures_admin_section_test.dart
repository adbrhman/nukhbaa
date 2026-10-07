/// The admin's matches page through its real providers and the real
/// `CompetitionApi`/`AdminApi`, over the auth harness's fake server: it
/// lists the month's fixtures with the hidden and test ones flagged,
/// filters them, hides one from its row at once, and hides a whole
/// selection only after a confirmation (migration 0098).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/fixtures_admin_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _real = '11111111-1111-4111-8111-111111111111';
const String _hidden = '22222222-2222-4222-8222-222222222222';
const String _test = '33333333-3333-4333-8333-333333333333';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

final class _Server {
  final List<http.Request> requests = <http.Request>[];
  final Set<String> hidden = <String>{_hidden};

  Map<String, Object?> _fixture(String id, String home, int day) =>
      <String, Object?>{
        'schema_version': 1,
        'season_id': 'm-10',
        'fixture_id': id,
        'home_team': home,
        'away_team': 'Away $home',
        'kickoff_at': '2026-10-${day}T18:00:00Z',
        if (hidden.contains(id)) 'hidden': true,
        if (id == _test) 'is_test': true,
      };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/months') {
      return _json(<Object?>[
        <String, Object?>{
          'id': 'm-10',
          'competition_id': 'c-1',
          'label': '10/2026',
          'start_at': '2026-09-30T21:00:00Z',
          'end_at': '2026-10-31T21:00:00Z',
        },
      ]);
    }
    if (path == '/seasons/m-10/fixtures') {
      return _json(<Object?>[
        _fixture(_real, 'Real', 20),
        _fixture(_hidden, 'Hidden', 19),
        _fixture(_test, 'Test', 18),
      ]);
    }
    if (path == '/admin/fixture-visibility') {
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      final bool hide = body['hidden'] == true;
      final List<String> changed = <String>[
        for (final Object? id in body['fixture_ids']! as List<Object?>)
          if (hidden.contains(id) != hide) id! as String,
      ];
      if (hide) {
        hidden.addAll(changed);
      } else {
        hidden.removeAll(changed);
      }
      return _json(<String, Object?>{
        'schema_version': 1,
        'changed': changed,
        'hidden': hide,
      });
    }
    return okMe(sampleUser);
  }

  List<http.Request> to(String path) => <http.Request>[
    for (final http.Request r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _open(WidgetTester tester, _Server server) async {
  // Tall enough that every row is built at once.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const Scaffold(body: FixturesAdminSection()),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(Key('admin.matches.row.$id'));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the month with every fixture, hidden and test ones '
      'flagged, and the filters narrow the list', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    expect(
      server.to('/seasons/m-10/fixtures').last.url.queryParameters,
      <String, String>{'include_hidden': 'true'},
    );
    expect(_row(_real), findsOneWidget);
    expect(_row(_hidden), findsOneWidget);
    expect(_row(_test), findsOneWidget);
    expect(find.byKey(const Key('admin.matches.hiddenBadge')), findsOneWidget);
    expect(find.byKey(const Key('admin.matches.testBadge')), findsOneWidget);

    await _tap(tester, 'admin.matches.filter.hidden');
    expect(_row(_hidden), findsOneWidget);
    expect(_row(_real), findsNothing);
    expect(_row(_test), findsNothing);

    await _tap(tester, 'admin.matches.filter.test');
    expect(_row(_test), findsOneWidget);
    expect(_row(_real), findsNothing);

    await _tap(tester, 'admin.matches.filter.visible');
    expect(_row(_real), findsOneWidget);
    expect(_row(_hidden), findsNothing);
    expect(_row(_test), findsNothing);
  });

  testWidgets('hiding from the row goes to the server at once, and the row '
      'comes back flagged', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    await _tap(tester, 'admin.matches.toggle.$_real');

    final List<http.Request> sent = server.to('/admin/fixture-visibility');
    expect(sent, hasLength(1));
    expect(jsonDecode(sent.single.body), <String, Object?>{
      'schema_version': 1,
      'fixture_ids': <Object?>[_real],
      'hidden': true,
    });
    expect(find.byKey(const Key('admin.matches.result')), findsOneWidget);
    expect(
      find.byKey(const Key('admin.matches.hiddenBadge')),
      findsNWidgets(2),
    );

    await _tap(tester, 'admin.matches.toggle.$_hidden');
    expect(
      jsonDecode(server.to('/admin/fixture-visibility').last.body),
      containsPair('hidden', false),
    );
  });

  testWidgets('a whole selection is hidden only after the confirmation', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);

    await _tap(tester, 'admin.matches.selectAll');
    await _tap(tester, 'admin.matches.bulkHide');
    expect(find.byKey(const Key('admin.matches.bulkConfirm')), findsOneWidget);

    await _tap(tester, 'admin.matches.bulkConfirm.cancel');
    expect(server.to('/admin/fixture-visibility'), isEmpty);

    await _tap(tester, 'admin.matches.bulkHide');
    await _tap(tester, 'admin.matches.bulkConfirm.ok');

    final List<http.Request> sent = server.to('/admin/fixture-visibility');
    expect(sent, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(sent.single.body) as Map<String, Object?>;
    expect((body['fixture_ids']! as List<Object?>).toSet(), <Object?>{
      _real,
      _hidden,
      _test,
    });
    expect(body['hidden'], true);
    expect(server.hidden, <String>{_real, _hidden, _test});
    expect(
      find.byKey(const Key('admin.matches.hiddenBadge')),
      findsNWidgets(3),
    );
  });

  testWidgets('selecting one row offers to act on that row alone', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);

    await _tap(tester, 'admin.matches.select.$_hidden');
    await _tap(tester, 'admin.matches.bulkShow');
    await _tap(tester, 'admin.matches.bulkConfirm.ok');

    final Map<String, Object?> body =
        jsonDecode(server.to('/admin/fixture-visibility').single.body)
            as Map<String, Object?>;
    expect(body['fixture_ids'], <Object?>[_hidden]);
    expect(body['hidden'], false);
    expect(find.byKey(const Key('admin.matches.hiddenBadge')), findsNothing);
  });
}
