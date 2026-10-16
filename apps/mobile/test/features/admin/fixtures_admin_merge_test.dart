/// Merging a copy of a match from the admin's matches page (script 95,
/// migration 0176), through the real providers and the real `AdminApi`
/// over the auth harness's fake server: the copy's row opens the merge,
/// the copy kept is picked from the copies of the match, the preview says
/// what moves and what stays, and only the confirmation merges.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/fixtures_admin_section.dart';
import 'package:mobile/features/admin/widgets/fixture_merge_dialog.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _copy = 'fde6264d-0000-4000-8000-000000000001';
const String _kept = 'a2e41db8-0000-4000-8000-000000000001';
const String _hiddenCopy = 'b0b0b0b0-0000-4000-8000-000000000001';
const String _test = '33333333-3333-4333-8333-333333333333';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _report({required bool applied}) => <String, Object?>{
  'schema_version': 1,
  'moved': 3,
  'doubles_moved': 1,
  'doubles_dropped': 1,
  'both_predicted': 1,
  'late': 0,
  'not_participant': 0,
  'link_moved': false,
  'kept_has_result': true,
  'applied': applied,
  'rescored': applied,
};

Map<String, Object?> _copyRow(
  String id, {
  bool hidden = false,
  bool self = false,
  int predictions = 3,
}) => <String, Object?>{
  'fixture_id': id,
  'home_team': 'سالزبورغ',
  'away_team': 'ميلان',
  'kickoff_at': '2026-10-15T19:00:00.000Z',
  'hidden': hidden,
  'predictions': predictions,
  'doubles': 0,
  'has_result': !self,
  'linked': false,
  'is_self': self,
};

final class _Server {
  _Server({this.keptVisible = true, this.refuse = false});

  final bool keptVisible;
  final bool refuse;
  final List<http.Request> requests = <http.Request>[];
  bool merged = false;

  Map<String, Object?> _fixture(String id, String home) => <String, Object?>{
    'schema_version': 1,
    'season_id': 'm-10',
    'fixture_id': id,
    'home_team': home,
    'away_team': 'ميلان',
    'kickoff_at': '2026-10-15T19:00:00Z',
    if (id == _copy && merged) 'hidden': true,
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
        _fixture(_copy, 'سالزبورج'),
        _fixture(_kept, 'سالزبورغ'),
        _fixture(_test, 'تجريبي'),
      ]);
    }
    if (path == '/admin/fixtures/$_copy/copies') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'copies': <Object?>[
          _copyRow(_copy, self: true),
          _copyRow(_kept, hidden: !keptVisible, predictions: 41),
          _copyRow(_hiddenCopy, hidden: true, predictions: 0),
        ],
      });
    }
    if (path == '/admin/fixtures/$_copy/merge') {
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      final bool apply = body['apply'] == true;
      if (apply && refuse) {
        return _json(<String, Object?>{
          'schema_version': 1,
          'code': 'competition.fixture_merge_refused',
          'message': 'دُمجت هذه النسخة من قبل.',
        }, 409);
      }
      if (apply) merged = true;
      return _json(_report(applied: apply));
    }
    return okMe(sampleUser);
  }

  List<http.Request> to(String path) => <http.Request>[
    for (final http.Request r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _open(WidgetTester tester, _Server server) async {
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

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

FilledButton _confirm(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('admin.merge.confirm')));

void main() {
  testWidgets('the copy is merged into the copy kept after a preview; the '
      'list reloads and says what moved', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    expect(find.byKey(const Key('admin.matches.merge.$_test')), findsNothing);
    await _tap(tester, 'admin.matches.merge.$_copy');
    expect(find.byKey(const Key('admin.merge.dialog')), findsOneWidget);
    expect(server.to('/admin/fixtures/$_copy/copies'), hasLength(1));
    expect(
      find.byKey(const Key('admin.merge.copy.$_copy')),
      findsNothing,
      reason: 'the copy itself is not a choice',
    );
    expect(_confirm(tester).onPressed, isNull);

    // A hidden copy cannot be kept.
    await _tap(tester, 'admin.merge.copy.$_hiddenCopy');
    expect(server.to('/admin/fixtures/$_copy/merge'), isEmpty);

    await _tap(tester, 'admin.merge.copy.$_kept');
    final List<http.Request> previews = server.to(
      '/admin/fixtures/$_copy/merge',
    );
    expect(jsonDecode(previews.single.body), <String, Object?>{
      'schema_version': 1,
      'into': _kept,
      'apply': false,
    });
    expect(
      find.text(
        'يُنقل 3 من التوقعات إلى النسخة التي تبقى كما هي، منها 1 مضاعفة.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('بلا مضاعفة'), findsOneWidget);
    expect(find.textContaining('توقّعوا النسختين'), findsOneWidget);
    expect(_confirm(tester).onPressed, isNotNull);
    final int listReads = server.to('/seasons/m-10/fixtures').length;

    await _tap(tester, 'admin.merge.confirm');
    final List<http.Request> merges = server.to('/admin/fixtures/$_copy/merge');
    expect(merges, hasLength(2));
    expect(jsonDecode(merges.last.body), containsPair('apply', true));
    expect(find.byKey(const Key('admin.merge.dialog')), findsNothing);
    expect(find.byKey(const Key('admin.matches.mergeResult')), findsOneWidget);
    expect(
      find.text(
        'دُمجت النسخة: نُقل 3 من التوقعات، 1 منها بلا مضاعفة، '
        'واحتُسبت النقاط.',
      ),
      findsOneWidget,
    );
    expect(server.to('/seasons/m-10/fixtures').length, greaterThan(listReads));
    expect(find.byKey(const Key('admin.matches.hiddenBadge')), findsOneWidget);
  });

  testWidgets('a refused merge stays in the dialog with its reason', (
    tester,
  ) async {
    final _Server server = _Server(refuse: true);
    await _open(tester, server);

    await _tap(tester, 'admin.matches.merge.$_copy');
    await _tap(tester, 'admin.merge.copy.$_kept');
    await _tap(tester, 'admin.merge.confirm');

    expect(find.byKey(const Key('admin.merge.dialog')), findsOneWidget);
    expect(find.byKey(const Key('admin.merge.error')), findsOneWidget);
    expect(find.textContaining('دُمجت هذه النسخة من قبل.'), findsOneWidget);
    expect(find.byKey(const Key('admin.matches.mergeResult')), findsNothing);

    await _tap(tester, 'admin.merge.cancel');
    expect(find.byKey(const Key('admin.merge.dialog')), findsNothing);
  });

  testWidgets('with no visible copy to keep, the dialog says what to do', (
    tester,
  ) async {
    final _Server server = _Server(keptVisible: false);
    await _open(tester, server);

    await _tap(tester, 'admin.matches.merge.$_copy');

    expect(find.byKey(const Key('admin.merge.none')), findsOneWidget);
    expect(_confirm(tester).onPressed, isNull);
  });

  test('the preview names what stays and why', () {
    final List<String> lines = fixtureMergePreviewLines(
      const FixtureMergeReportDto(
        moved: 0,
        doublesMoved: 0,
        doublesDropped: 0,
        bothPredicted: 0,
        late: 2,
        notParticipant: 1,
        linkMoved: false,
        keptHasResult: true,
        applied: false,
        rescored: false,
      ),
    );

    expect(lines.first, 'لا توقّع يُنقل من هذه النسخة.');
    expect(lines, contains('يبقى 2: أُرسلت بعد بداية المباراة.'));
    expect(lines.any((l) => l.contains('ليسوا في موسم')), isTrue);
    expect(lines.any((l) => l.contains('تُحتسب نقاط')), isFalse);
  });

  test('a merge whose rescore waits says it', () {
    expect(
      fixtureMergeResultMessage(
        const FixtureMergeReportDto(
          moved: 1,
          doublesMoved: 0,
          doublesDropped: 0,
          bothPredicted: 0,
          late: 0,
          notParticipant: 0,
          linkMoved: false,
          keptHasResult: true,
          applied: true,
          rescored: false,
        ),
      ),
      'دُمجت النسخة: نُقل 1 من التوقعات، وتُحتسب النقاط في الدورة التالية.',
    );
  });
}
