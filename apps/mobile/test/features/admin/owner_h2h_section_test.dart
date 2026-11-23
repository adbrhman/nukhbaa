/// تبويب «المواجهات» للمالك (السكربت 304) عبر المزوّدات الحقيقية و`AdminApi`
/// الحقيقي فوق خادم الاختبار: ثلاثة أقفال لا يتغير أحدها إلا بسبب مكتوب،
/// وتشغيل المهام الآن، وجولات الشهر، والكأس بمساراته الثلاثة. ويظهر في
/// «الإدارة العامة للمالك» تبويباً أخيراً.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/admin_shell.dart';
import 'package:mobile/features/admin/screens/sections/owner_h2h_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const AuthenticatedUserDto _owner = AuthenticatedUserDto(
  userId: 'u-owner-id',
  role: 'admin',
  status: 'active',
  email: 'owner@example.com',
  isOwner: true,
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

H2hCupPlayerDto _p(String id, String name, int group) => H2hCupPlayerDto(
  userId: id,
  displayName: name,
  groupNumber: group,
  isMe: false,
);

final H2hCupPlayerDto _sami = _p('u-1', 'سامي', 1);
final H2hCupPlayerDto _omar = _p('u-2', 'عمر', 2);
final H2hCupPlayerDto _noura = _p('u-3', 'نورة', 3);
final H2hCupPlayerDto _huda = _p('u-4', 'هدى', 4);

OwnerH2hCupPathDto _path(int place, {bool decided = false}) =>
    OwnerH2hCupPathDto(
      place: place,
      entrants: <H2hCupPlayerDto>[_sami, _omar, _noura, _huda],
      stages: <H2hCupStageDto>[
        H2hCupStageDto(
          round: 'semi',
          cupDay: 1,
          expectedDay: 20,
          phase: decided ? 'decided' : 'scheduled',
          attempt: 1,
          day: '2026-11-22',
          fixtureCount: 8,
          pairs: <H2hCupPairDto>[
            H2hCupPairDto(
              slot: 1,
              home: _sami,
              away: _noura,
              isMine: false,
              decided: decided,
              outcome: decided ? 'points' : null,
              winnerUserId: decided ? 'u-1' : null,
              homePoints: decided ? 9 : null,
              awayPoints: decided ? 4 : null,
            ),
          ],
        ),
        const H2hCupStageDto(
          round: 'final',
          cupDay: 2,
          expectedDay: 21,
          phase: 'waiting',
          attempt: 1,
          pairs: <H2hCupPairDto>[],
        ),
      ],
    );

OwnerH2hCupDto _cup(String month) => OwnerH2hCupDto(
  monthStart: month,
  months: const <OwnerH2hCupMonthDto>[
    OwnerH2hCupMonthDto(monthStart: '2026-11-01', hasCup: true),
    OwnerH2hCupMonthDto(monthStart: '2026-12-01', hasCup: false),
  ],
  rounds: const <OwnerH2hCupRoundDto>[
    OwnerH2hCupRoundDto(
      number: 1,
      day: '2026-11-03',
      fixtureCount: 8,
      locked: true,
      bySystem: true,
    ),
    OwnerH2hCupRoundDto(
      number: 2,
      day: '2026-11-04',
      fixtureCount: 7,
      locked: false,
      bySystem: false,
    ),
  ],
  paths: month == '2026-11-01'
      ? <OwnerH2hCupPathDto>[_path(1, decided: true), _path(2), _path(3)]
      : const <OwnerH2hCupPathDto>[],
);

final class _Server {
  _Server({this.withSwitches = true});

  final bool withSwitches;
  final Map<String, bool> on = <String, bool>{
    'h2h_rounds': true,
    'h2h_cup': true,
    'h2h_cup_crowning': true,
  };
  final List<http.Request> requests = <http.Request>[];

  Map<String, Object?> _line(String key) => {
    'key': key,
    'is_on': on[key],
    'reason': null,
    'changed_by': null,
    'changed_at': '2026-11-20T00:00:00.000Z',
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/owner/switches') {
      return _json({
        'schema_version': 1,
        'switches': [
          if (withSwitches)
            for (final k in on.keys) _line(k),
        ],
      });
    }
    if (path.startsWith('/owner/switches/') && request.method == 'PUT') {
      final String key = path.substring('/owner/switches/'.length);
      final Map<String, Object?> body =
          (jsonDecode(request.body) as Map<Object?, Object?>)
              .cast<String, Object?>();
      on[key] = body['is_on']! as bool;
      return _json(_line(key));
    }
    if (path == '/owner/h2h-cup') {
      return _json(
        _cup(request.url.queryParameters['month'] ?? '2026-11-01').toJson(),
      );
    }
    if (path == '/admin/h2h/jobs' && request.method == 'POST') {
      return _json({
        'approved': 1,
        'locked': 2,
        'closed_months': 0,
        'drawn_seats': 0,
      });
    }
    return okMe(_owner);
  }

  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _open(
  WidgetTester tester,
  _Server server,
  Widget body, {
  double textScale = 1.0,
}) async {
  const Size size = Size(1080, 9000);
  const double ratio = 3.0;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        home: MediaQuery(
          data: MediaQueryData(
            size: size / ratio,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: body),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  testWidgets('the owner reads the locks, the rounds and the three paths', (
    tester,
  ) async {
    await _open(tester, _Server(), const OwnerH2hSection());

    expect(
      find.byKey(const Key('owner.h2h.switch.h2h_rounds')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('owner.h2h.switch.h2h_cup')), findsOneWidget);
    expect(
      find.byKey(const Key('owner.h2h.switch.h2h_cup_crowning')),
      findsOneWidget,
    );
    expect(_text(tester, 'owner.h2h.switch.h2h_cup.state'), contains('يعمل'));
    expect(_text(tester, 'owner.h2h.rounds.summary'), contains('2 جولة'));
    expect(_text(tester, 'owner.h2h.rounds.summary'), contains('1 مقفلة'));
    expect(_text(tester, 'owner.h2h.round.2'), contains('مشرف'));
    expect(find.byKey(const Key('owner.h2h.path.1')), findsOneWidget);
    expect(find.byKey(const Key('owner.h2h.path.2')), findsOneWidget);
    expect(find.byKey(const Key('owner.h2h.path.3')), findsOneWidget);
    expect(_text(tester, 'owner.h2h.path.1.entrants'), contains('نورة'));
    expect(find.byKey(const Key('owner.h2h.pair.1.semi.1')), findsOneWidget);
    expect(find.text('9 - 4'), findsOneWidget);
    expect(
      _text(tester, 'owner.h2h.outcome.1.semi.1'),
      contains('بفارق النقاط'),
    );
    expect(_text(tester, 'owner.h2h.stage.2.final'), contains('بانتظار'));
  });

  testWidgets('a lock turns only once a reason is typed', (tester) async {
    final server = _Server();
    await _open(tester, server, const OwnerH2hSection());

    await tester.tap(
      find.byKey(const Key('owner.h2h.switch.h2h_cup_crowning')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('owner.h2h.dialog.notice')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('owner.h2h.dialog.confirm')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('owner.h2h.reason')),
      'نتحقق من النقاط',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('owner.h2h.dialog.confirm')));
    await tester.pumpAndSettle();

    final put = server.to('/owner/switches/h2h_cup_crowning').single;
    expect(put.method, 'PUT');
    final body = jsonDecode(put.body) as Map<String, Object?>;
    expect(body['is_on'], false);
    expect(body['reason'], 'نتحقق من النقاط');
    expect(
      _text(tester, 'owner.h2h.switch.h2h_cup_crowning.state'),
      contains('موقوف'),
    );
  });

  testWidgets('cancelling the dialog changes nothing', (tester) async {
    final server = _Server();
    await _open(tester, server, const OwnerH2hSection());

    await tester.tap(find.byKey(const Key('owner.h2h.switch.h2h_rounds')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('owner.h2h.dialog.cancel')));
    await tester.pumpAndSettle();

    expect(server.to('/owner/switches/h2h_rounds'), isEmpty);
  });

  testWidgets('without migration 0225 the lock says so', (tester) async {
    await _open(tester, _Server(withSwitches: false), const OwnerH2hSection());

    expect(
      _text(tester, 'owner.h2h.switch.h2h_rounds.missing'),
      contains('0225'),
    );
  });

  testWidgets('run the jobs now', (tester) async {
    final server = _Server();
    await _open(tester, server, const OwnerH2hSection());

    await tester.tap(find.byKey(const Key('owner.h2h.run')));
    await tester.pumpAndSettle();

    expect(server.to('/admin/h2h/jobs'), hasLength(1));
    expect(find.textContaining('اعتُمدت 1'), findsOneWidget);
  });

  testWidgets('picking another month asks for it', (tester) async {
    final server = _Server();
    await _open(tester, server, const OwnerH2hSection());

    await tester.tap(find.byKey(const Key('owner.h2h.month.1')));
    await tester.pumpAndSettle();

    expect(
      server.to('/owner/h2h-cup').last.url.queryParameters['month'],
      '2026-12-01',
    );
    expect(find.byKey(const Key('owner.h2h.path.1')), findsNothing);
  });

  testWidgets('the owner page has the tab, last', (tester) async {
    await _open(tester, _Server(), const OwnerGeneralSection());

    expect(find.byKey(const Key('admin.owner.tab.7')), findsOneWidget);
    expect(find.text('المواجهات'), findsOneWidget);
  });

  testWidgets('fits 360px at text x2', (tester) async {
    await _open(tester, _Server(), const OwnerH2hSection(), textScale: 2);

    expect(find.byKey(const Key('owner.h2h.path.1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
