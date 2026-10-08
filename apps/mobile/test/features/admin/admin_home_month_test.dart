/// The month card and the crowning reminder on the admin home (2026-10-08),
/// drawn through the real home section with the real theme; the providers
/// are overridden and the clock is fixed. The month logic is checked on its
/// own pure functions as well.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/admin_sections.dart';
import 'package:mobile/features/admin/screens/sections/admin_home_section.dart';
import 'package:mobile/features/admin/widgets/admin_month_card.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

// 2026-10-08 15:00 Riyadh (12:00 UTC).
final DateTime _now = DateTime.utc(2026, 10, 8, 12);

SeasonDto _month(String id, String label, DateTime start, DateTime end) =>
    SeasonDto(
      id: id,
      competitionId: 'c-1',
      label: label,
      startAt: start,
      endAt: end,
    );

// Calendar months in Riyadh (UTC+3): each starts at 21:00 UTC the day before.
final SeasonDto _aug = _month(
  's-08',
  '08/2026',
  DateTime.utc(2026, 7, 31, 21),
  DateTime.utc(2026, 8, 31, 21),
);
final SeasonDto _sep = _month(
  's-09',
  '09/2026',
  DateTime.utc(2026, 8, 31, 21),
  DateTime.utc(2026, 9, 30, 21),
);
final SeasonDto _oct = _month(
  's-10',
  '10/2026',
  DateTime.utc(2026, 9, 30, 21),
  DateTime.utc(2026, 10, 31, 21),
);

ChampionCandidateDto _line(int rank, String id, String name, int points) =>
    ChampionCandidateDto(
      rank: rank,
      userId: id,
      displayName: name,
      points: points,
      exactCount: rank,
      decidedCount: 8,
      referralPoints: 0,
    );

ChampionCandidatesDto _board(
  SeasonDto month, {
  List<String> crowned = const <String>[],
  List<ChampionCandidateDto> lines = const <ChampionCandidateDto>[],
}) => ChampionCandidatesDto(
  seasonId: month.id,
  seasonLabel: month.label,
  ended: !_now.isBefore(month.endAt),
  unscoredFixtures: 0,
  crowned: crowned,
  candidates: lines,
);

final ChampionCandidatesDto _octBoard = _board(
  _oct,
  lines: <ChampionCandidateDto>[
    _line(1, 'u-semo', 'Semo', 13),
    _line(2, 'u-jaber', 'جابر عامر', 10),
    _line(3, 'u-ahmed', 'Ahmed algalal', 9),
  ],
);

Future<List<AdminSection>> _pump(
  WidgetTester tester,
  Future<AdminMonthPulse> Function() pulse, {
  Size size = const Size(900, 6000),
  double textScale = 1,
}) async {
  // Tall: the whole page is built, so a "findsNothing" is not a lazy list.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final List<AdminSection> opened = <AdminSection>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminDashboardProvider.overrideWith(
          (ref) async => const AdminDashboardSnapshot(
            stats: UserStatsDto(total: 0, active: 0, suspended: 0),
            auditLog: AuditLogDto(entries: <AuditEntryDto>[]),
            competitions: <CompetitionDto>[],
            currentMonthFixtures: <CurrentMonthFixtureItemDto>[],
          ),
        ),
        adminAttentionProvider.overrideWith(
          (ref) async => const AdminAttention(heldReferrals: 0, freshErrors: 0),
        ),
        adminMonthPulseProvider.overrideWith((ref) => pulse()),
        adminRetentionProvider.overrideWith(
          (ref) async => const AdminRetentionDto(
            today: '2026-10-08',
            weeks: <RetentionWeekDto>[],
            cohorts: <RetentionCohortDto>[],
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: AdminHomeSection(onNavigate: opened.add, now: () => _now),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The last card is built: the list was built to its end.
  expect(find.byKey(const Key('admin.dashboard.activity.all')), findsOneWidget);
  return opened;
}

Finder _in(String key, Finder finder) =>
    find.descendant(of: find.byKey(Key(key)), matching: finder);

void main() {
  group('adminMonthsAt', () {
    test('picks the running month and the ended ones, newest first', () {
      final picked = adminMonthsAt(<SeasonDto>[_aug, _oct, _sep], _now);
      expect(picked.current?.id, 's-10');
      expect(picked.recentEnded.map((SeasonDto m) => m.id), <String>[
        's-09',
        's-08',
      ]);
    });

    test('a month ends at its endAt, not after it', () {
      final picked = adminMonthsAt(<SeasonDto>[_sep, _oct], _oct.startAt);
      expect(picked.current?.id, 's-10');
      expect(picked.recentEnded.single.id, 's-09');
    });

    test('between months there is no current month', () {
      final picked = adminMonthsAt(<SeasonDto>[_sep], _now);
      expect(picked.current, isNull);
    });

    test('looks back over the last three ended months only', () {
      final List<SeasonDto> months = <SeasonDto>[
        for (int m = 1; m <= 9; m++)
          _month(
            's-$m',
            '0$m/2026',
            DateTime.utc(2026, m),
            DateTime.utc(2026, m + 1),
          ),
      ];
      final picked = adminMonthsAt(months, _now);
      expect(picked.recentEnded.map((SeasonDto m) => m.id), <String>[
        's-9',
        's-8',
        's-7',
      ]);
    });
  });

  test(
    'uncrownedMonths: players and no champion; empty boards wait for no one',
    () {
      final List<SeasonDto> uncrowned = uncrownedMonths(
        <SeasonDto>[_sep, _aug],
        <String, ChampionCandidatesDto>{
          's-09': _board(
            _sep,
            lines: <ChampionCandidateDto>[_line(1, 'u', 'U', 4)],
          ),
          's-08': _board(_aug),
        },
      );
      expect(uncrowned.map((SeasonDto m) => m.id), <String>['s-09']);

      final List<SeasonDto> crowned = uncrownedMonths(
        <SeasonDto>[_sep],
        <String, ChampionCandidatesDto>{
          's-09': _board(
            _sep,
            crowned: <String>['u'],
            lines: <ChampionCandidateDto>[_line(1, 'u', 'U', 4)],
          ),
        },
      );
      expect(crowned, isEmpty);
    },
  );

  test('monthTimeLeft and pointsLabel read as Arabic counts', () {
    expect(monthTimeLeft(_oct.endAt, _now), 'بقي 24 يوماً');
    expect(
      monthTimeLeft(_oct.endAt, _oct.endAt.subtract(const Duration(hours: 5))),
      'بقي يوم واحد',
    );
    expect(
      monthTimeLeft(_oct.endAt, _oct.endAt.subtract(const Duration(days: 2))),
      'بقي يومان',
    );
    expect(
      monthTimeLeft(_oct.endAt, _oct.endAt.subtract(const Duration(days: 5))),
      'بقي 5 أيام',
    );
    expect(monthTimeLeft(_oct.endAt, _oct.endAt), 'انتهى الشهر');
    expect(pointsLabel(13), '13 نقطة');
    expect(pointsLabel(9), '9 نقاط');
    expect(pointsLabel(2), 'نقطتان');
  });

  testWidgets('the card shows the month, its time left and its top', (
    tester,
  ) async {
    final List<AdminSection> opened = await _pump(
      tester,
      () async => AdminMonthPulse(
        current: _oct,
        board: _octBoard,
        uncrowned: const <SeasonDto>[],
      ),
    );

    expect(
      _in('admin.dashboard.month', find.text('مسابقة شهر 10')),
      findsOneWidget,
    );
    expect(
      _in('admin.dashboard.month', find.text('بقي 24 يوماً')),
      findsOneWidget,
    );
    expect(
      _in('admin.dashboard.month.line.u-semo', find.text('13 نقطة')),
      findsOneWidget,
    );
    expect(
      _in('admin.dashboard.month.line.u-ahmed', find.text('9 نقاط')),
      findsOneWidget,
    );
    // Nothing to crown: the reminder row is absent.
    expect(
      find.byKey(const Key('admin.dashboard.attention.crowning')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('admin.dashboard.month.open')));
    await tester.pump();
    expect(opened, <AdminSection>[AdminSection.champions]);
  });

  testWidgets('an ended month with players and no champion needs you', (
    tester,
  ) async {
    final List<AdminSection> opened = await _pump(
      tester,
      () async => AdminMonthPulse(
        current: _oct,
        board: _octBoard,
        uncrowned: <SeasonDto>[_sep],
      ),
    );

    expect(
      _in('admin.dashboard.attention.crowning', find.text('1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.dashboard.attention.clear')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('admin.dashboard.attention.crowning')),
    );
    await tester.pump();
    expect(opened, <AdminSection>[AdminSection.champions]);
  });

  testWidgets('a failed read says so on the card and in the reminder', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => throw const AppError.transient('net.down', 'offline'),
    );

    expect(
      find.byKey(const Key('admin.dashboard.month.error')),
      findsOneWidget,
    );
    expect(find.text('تعذّر التحقق من التتويج'), findsOneWidget);
    expect(
      find.byKey(const Key('admin.dashboard.attention.clear')),
      findsNothing,
    );
  });

  testWidgets('between months and with an empty board the card says so', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => const AdminMonthPulse(
        current: null,
        board: null,
        uncrowned: <SeasonDto>[],
      ),
    );
    expect(find.byKey(const Key('admin.dashboard.month.none')), findsOneWidget);
  });

  testWidgets('a month with no points yet reads as empty', (tester) async {
    await _pump(
      tester,
      () async => AdminMonthPulse(
        current: _oct,
        board: _board(_oct),
        uncrowned: const <SeasonDto>[],
      ),
    );
    expect(
      find.byKey(const Key('admin.dashboard.month.empty')),
      findsOneWidget,
    );
  });

  testWidgets('on a phone at double text size the card and reminder fit', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => AdminMonthPulse(
        current: _oct,
        board: _octBoard,
        uncrowned: <SeasonDto>[_sep, _aug],
      ),
      size: const Size(360, 6000),
      textScale: 2,
    );
    expect(
      find.byKey(const Key('admin.dashboard.month.line.u-jaber')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.dashboard.attention.crowning')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
