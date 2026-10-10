/// Widget tests for [H2hScreen] over the real [AuthApi] and the real
/// [ApiTransport], with only the socket faked ([buildAuthHarness]'s
/// `MockClient`). The tab asks `GET /me/h2h-league` through
/// `myH2hLeagueProvider` and draws what came back, so a tab that stopped
/// asking, asked the wrong path, or re-decided the server's phases, table,
/// zones or results fails here.
///
/// The views are tall wherever a list's last item is checked: a ListView
/// does not build what is off screen.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_screen.dart';
import 'package:mobile/features/h2h/h2h_texts.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _okJson(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Future<http.Response> Function(http.Request) _serve(MyH2hLeagueDto league) {
  return (http.Request request) async {
    if (request.url.path == '/me/h2h-league') return _okJson(league.toJson());
    return http.Response('not found', 404);
  };
}

MyH2hLeagueDto _waiting(String state) => MyH2hLeagueDto(
  state: state,
  monthStart: '2026-10-01',
  startsOn: '2026-11-01',
  isPilot: false,
  myRank: 0,
  promotionZone: 0,
  relegationZone: 0,
  standings: const <H2hStandingDto>[],
  rounds: const <H2hRoundViewDto>[],
);

H2hStandingDto _line(
  int rank,
  String id,
  String name,
  int points, {
  bool me = false,
  List<String> form = const <String>[],
}) => H2hStandingDto(
  rank: rank,
  userId: id,
  displayName: name,
  played: form.length,
  won: form.where((r) => r == 'win').length,
  drawn: form.where((r) => r == 'draw').length,
  lost: form.where((r) => r == 'loss').length,
  leaguePoints: points,
  pointsFor: 10 * points,
  exactCount: 0,
  form: form,
  isMe: me,
);

const H2hRoundViewDto _settled = H2hRoundViewDto(
  round: 1,
  day: '2026-11-01',
  status: 'settled',
  fixtureCount: 7,
  opponentUserId: 'u-d',
  opponentName: 'عمر',
  myPoints: 10,
  opponentPoints: 6,
  result: 'win',
  firstKickoff: '2026-11-01T12:00:00.000Z',
);

const H2hRoundViewDto _voided = H2hRoundViewDto(
  round: 3,
  day: '2026-11-07',
  status: 'voided',
  fixtureCount: 0,
);

/// A group of four in the second division: two go up, two go down. Round 1
/// was won, round 2 is [second], round 3 was void, round 4 is next (open)
/// and round 5 after it.
MyH2hLeagueDto _open({
  bool pilot = false,
  H2hRoundViewDto second = const H2hRoundViewDto(
    round: 2,
    day: '2026-11-04',
    status: 'live',
    fixtureCount: 8,
    opponentUserId: 'u-b',
    opponentName: 'نورة',
    myPoints: 3,
    opponentPoints: 5,
    result: 'loss',
    firstKickoff: '2026-11-04T12:00:00.000Z',
  ),
  int daysLeft = 21,
}) => MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-11-01',
  startsOn: '2026-11-01',
  isPilot: pilot,
  division: 2,
  groupIndex: 0,
  myRank: 1,
  promotionZone: 2,
  relegationZone: 2,
  daysLeft: daysLeft,
  standings: <H2hStandingDto>[
    _line(1, 'u-me', 'سامي', 3, me: true, form: const <String>['win']),
    _line(2, 'u-b', 'نورة', 1, form: const <String>['draw']),
    _line(3, 'u-c', '', 1, form: const <String>['draw']),
    _line(4, 'u-d', 'عمر', 0, form: const <String>['loss']),
  ],
  rounds: <H2hRoundViewDto>[
    _settled,
    second,
    _voided,
    const H2hRoundViewDto(
      round: 4,
      day: '2026-11-12',
      status: 'open',
      fixtureCount: 9,
      opponentUserId: 'u-d',
      opponentName: 'عمر',
      firstKickoff: '2026-11-12T15:00:00.000Z',
    ),
    const H2hRoundViewDto(
      round: 5,
      day: '2026-11-15',
      status: 'upcoming',
      fixtureCount: 6,
      opponentUserId: 'u-c',
      opponentName: '',
    ),
  ],
);

/// Round 2 is the next one: open, its first kickoff at 15:00 UTC on the
/// 4th; nothing is being played.
MyH2hLeagueDto _openNext() => _open(
  second: const H2hRoundViewDto(
    round: 2,
    day: '2026-11-04',
    status: 'open',
    fixtureCount: 8,
    opponentUserId: 'u-b',
    opponentName: 'نورة',
    firstKickoff: '2026-11-04T15:00:00.000Z',
  ),
);

Future<void> _pump(
  WidgetTester tester,
  MyH2hLeagueDto league, {
  Size size = const Size(1080, 4000),
  double textScale = 1,
  int section = 0,
  VoidCallback? onOpenMatches,
  DateTime Function()? now,
  ValueNotifier<bool>? visible,
}) async {
  final AuthHarness harness = buildAuthHarness(
    _serve(league),
    seedToken: 'jwt',
  );
  addTearDown(harness.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final Widget screen = H2hScreen(
    initialSection: section,
    onOpenMatches: onOpenMatches,
    now: now,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: visible == null
            ? screen
            : ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (BuildContext context, bool on, Widget? child) =>
                    TickerMode(enabled: on, child: child!),
                child: screen,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inside(String key, Finder finder) =>
    find.descendant(of: find.byKey(Key(key)), matching: finder);

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  group('without a seat', () {
    testWidgets('before the league opens: the date and the rules', (
      tester,
    ) async {
      await _pump(tester, _waiting('not_started'));

      expect(find.byKey(const Key('h2h.title')), findsOneWidget);
      expect(find.byKey(const Key('h2h.state.not_started')), findsOneWidget);
      expect(find.text('ينطلق 1 نوفمبر'), findsOneWidget);
      expect(find.byKey(const Key('h2h.rules')), findsOneWidget);
      expect(find.byKey(const Key('h2h.banner')), findsNothing);
      expect(find.byKey(const Key('h2h.sections')), findsNothing);
    });

    testWidgets('outside the draw: says why', (tester) async {
      await _pump(tester, _waiting('not_in_draw'));

      expect(find.byKey(const Key('h2h.state.not_in_draw')), findsOneWidget);
      expect(find.text('لست في قرعة هذا الشهر'), findsOneWidget);
    });
  });

  group('the division card', () {
    testWidgets('division, month, place, round and days left', (tester) async {
      await _pump(tester, _open());

      expect(_text(tester, 'h2h.division'), 'الدرجة الثانية');
      expect(_text(tester, 'h2h.month'), 'دوري المواجهات · نوفمبر 2026');
      expect(_text(tester, 'h2h.myRank'), '1 من 4');
      // Round 2 is being played: it is the one that matters now.
      expect(_text(tester, 'h2h.progress'), 'الجولة 2 من 19 كحد أقصى');
      expect(_text(tester, 'h2h.daysLeft'), 'باقي 21 يومًا');
      expect(find.byKey(const Key('h2h.pilot')), findsNothing);
    });

    testWidgets('a pilot month says its results do not count', (tester) async {
      await _pump(tester, _open(pilot: true));

      expect(find.byKey(const Key('h2h.pilot')), findsOneWidget);
    });

    testWidgets('the last day of the month says so', (tester) async {
      await _pump(tester, _open(daysLeft: 0));

      expect(_text(tester, 'h2h.daysLeft'), 'آخر يوم في الشهر');
    });
  });

  group('the match section', () {
    testWidgets('the live round leads, with its score so far', (tester) async {
      await _pump(tester, _open());

      expect(
        _text(tester, 'h2h.featured.heading'),
        'الجولة 2 · مواجهة اليوم · جارية',
      );
      expect(_text(tester, 'h2h.featured.mine'), '3');
      expect(_text(tester, 'h2h.featured.theirs'), '5');
      expect(
        _inside('h2h.featured', find.text('خسارة حتى الآن')),
        findsOneWidget,
      );
      expect(_inside('h2h.featured', find.text('نورة')), findsOneWidget);
      expect(_inside('h2h.featured', find.text('سامي')), findsOneWidget);
      expect(find.byKey(const Key('h2h.countdown')), findsNothing);
    });

    testWidgets('the next round counts down to its first kickoff', (
      tester,
    ) async {
      // 3 h 20 min 30 s before 15:00 UTC on the 4th.
      DateTime clock = DateTime.utc(2026, 11, 4, 11, 39, 30);
      await _pump(tester, _openNext(), now: () => clock);

      expect(
        _text(tester, 'h2h.featured.heading'),
        'الجولة 2 · المواجهة القادمة · 4 نوفمبر',
      );
      expect(_text(tester, 'h2h.countdown.value'), '3 س 20 د');
      expect(find.byKey(const Key('h2h.featured.score')), findsNothing);

      // Half a minute later the label moves to the next minute.
      clock = clock.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      expect(_text(tester, 'h2h.countdown.value'), '3 س 19 د');
    });

    testWidgets('out of sight the countdown stops, and catches up on return', (
      tester,
    ) async {
      DateTime clock = DateTime.utc(2026, 11, 4, 11, 39, 30);
      final ValueNotifier<bool> visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      await _pump(tester, _openNext(), now: () => clock, visible: visible);
      expect(_text(tester, 'h2h.countdown.value'), '3 س 20 د');

      visible.value = false;
      await tester.pump();
      clock = clock.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      // No timer ran while hidden: the label was not redrawn.
      expect(_text(tester, 'h2h.countdown.value'), '3 س 20 د');

      visible.value = true;
      await tester.pump();
      expect(_text(tester, 'h2h.countdown.value'), '3 س 15 د');
    });

    testWidgets('the matches button opens the matches', (tester) async {
      int opened = 0;
      await _pump(tester, _open(), onOpenMatches: () => opened++);

      await tester.tap(find.byKey(const Key('h2h.goToMatches')));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('without the shell there is no matches button', (tester) async {
      await _pump(tester, _open());

      expect(find.byKey(const Key('h2h.goToMatches')), findsNothing);
    });
  });

  group('the table section', () {
    testWidgets('server order, both zones, and the caller pinned', (
      tester,
    ) async {
      await _pump(tester, _open(), section: 1);

      expect(find.byKey(const Key('h2h.table.compact')), findsOneWidget);
      final List<double> tops = <double>[
        for (final String id in <String>['u-me', 'u-b', 'u-c', 'u-d'])
          tester.getTopLeft(find.byKey(Key('h2h.standing.$id'))).dy,
      ];
      expect(tops, orderedEquals(<double>[...tops]..sort()));

      final AppTokens t = tester.element(find.byType(H2hScreen)).tokens;
      Color? zone(String id) =>
          (tester
                      .widget<Container>(
                        find.byKey(Key('h2h.standing.$id.zone')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      expect(zone('u-me'), t.success);
      expect(zone('u-b'), t.success);
      expect(zone('u-c'), t.error);
      expect(zone('u-d'), t.error);
      expect(find.text('يصعد أول 2'), findsOneWidget);
      expect(find.text('يهبط آخر 2'), findsOneWidget);

      expect(_text(tester, 'h2h.standing.u-me.points'), '3');
      expect(_text(tester, 'h2h.standing.u-d.rank'), '4');
      // A member without a name is still a line, never a blank.
      expect(_inside('h2h.standing.u-c', find.text('لاعب')), findsOneWidget);

      expect(_text(tester, 'h2h.table.me.rank'), 'المركز 1 من 4');
      expect(_text(tester, 'h2h.table.me.points'), '3 ن');
    });

    testWidgets('at larger text each member is two lines, spelled out', (
      tester,
    ) async {
      await _pump(
        tester,
        _open(),
        section: 1,
        size: const Size(360, 4000),
        textScale: 1.3,
      );

      expect(find.byKey(const Key('h2h.table.lines')), findsOneWidget);
      expect(
        _text(tester, 'h2h.standing.u-me.record'),
        'لعب 1 · فوز 1 · تعادل 0 · خسارة 0 · نقاط التوقع 30',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the rounds section', () {
    testWidgets('every phase, the newest first, and when rounds come', (
      tester,
    ) async {
      await _pump(tester, _open(), section: 2);

      final List<double> tops = <double>[
        for (final int n in <int>[5, 4, 3, 2, 1])
          tester.getTopLeft(find.byKey(Key('h2h.round.$n'))).dy,
      ];
      expect(tops, orderedEquals(<double>[...tops]..sort()));

      expect(_inside('h2h.round.1', find.text('مكتملة')), findsOneWidget);
      expect(_inside('h2h.round.1', find.text('فوز')), findsOneWidget);
      expect(_text(tester, 'h2h.round.1.score'), '10 مقابل 6');
      expect(_inside('h2h.round.2', find.text('جارية')), findsOneWidget);
      expect(
        _inside('h2h.round.2', find.text('خسارة حتى الآن')),
        findsOneWidget,
      );
      expect(_inside('h2h.round.3', find.text('ملغاة')), findsOneWidget);
      expect(find.byKey(const Key('h2h.round.3.score')), findsNothing);
      expect(_inside('h2h.round.4', find.text('مفتوحة')), findsOneWidget);
      expect(_inside('h2h.round.4', find.text('ضد عمر')), findsOneWidget);
      expect(_inside('h2h.round.5', find.text('قادمة')), findsOneWidget);
      expect(_inside('h2h.round.5', find.text('ضد لاعب')), findsOneWidget);
      expect(find.text(h2hRoundsNote), findsOneWidget);
    });

    test('a version 1 server: upcoming reads as coming', () {
      expect(h2hRoundStatusLabel('upcoming'), 'قادمة');
      expect(h2hRoundStatusLabel('something-new'), 'قادمة');
    });
  });

  testWidgets('the rules open from the header, with rules 2 and 5 fixed', (
    tester,
  ) async {
    await _pump(tester, _open());

    await tester.tap(find.byKey(const Key('h2h.rulesButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('h2h.rulesSheet')), findsOneWidget);
    expect(
      _inside('h2h.rulesSheet', find.textContaining('يُعلن قبل يومه')),
      findsOneWidget,
    );
    expect(
      _inside('h2h.rulesSheet', find.textContaining('حتى 3 لاعبين')),
      findsOneWidget,
    );
    expect(
      _inside('h2h.rulesSheet', find.textContaining('المشرف')),
      findsNothing,
    );
  });

  for (final double scale in <double>[1.3, 2.0]) {
    testWidgets('a 360px phone at text x$scale draws every section', (
      tester,
    ) async {
      DateTime now() => DateTime.utc(2026, 11, 4, 11, 39, 30);
      for (int section = 0; section < 3; section++) {
        await tester.pumpWidget(const SizedBox.shrink());
        // Tall enough that the list builds its last item.
        await _pump(
          tester,
          section == 0 ? _openNext() : _open(),
          size: const Size(360, 9000),
          textScale: scale,
          section: section,
          now: now,
          onOpenMatches: () {},
        );
        expect(tester.takeException(), isNull, reason: 'section $section');
        expect(find.byKey(const Key('h2h.banner')), findsOneWidget);
      }
      expect(find.byKey(const Key('h2h.round.1')), findsOneWidget);
      expect(find.byKey(const Key('h2h.rounds.note')), findsOneWidget);
    });
  }

  testWidgets('the title stays at the start of the header', (tester) async {
    await _pump(tester, _open());

    final AppBar bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.centerTitle, isFalse);
  });

  testWidgets('a failed read shows the error under the tab header', (
    tester,
  ) async {
    final AuthHarness harness = buildAuthHarness(
      (http.Request request) async => http.Response(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'code': 'db.down',
          'message': 'down',
        }),
        503,
        headers: const {'content-type': 'application/json'},
      ),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const H2hScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('h2h.title')), findsOneWidget);
    expect(find.byKey(const Key('browse.error')), findsOneWidget);
  });
}
