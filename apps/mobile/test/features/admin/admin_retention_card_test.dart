/// The admin dashboard's retention card, through the real
/// [AdminRetentionCard] and [adminRetentionProvider]: three headline
/// figures, a row per week and per cohort, a dash where nobody can be
/// judged yet, the week in progress marked, an empty window said in words,
/// and a failed read said instead of a spinner.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/widgets/admin_retention_card.dart';
import 'package:shared/shared.dart';

/// A figure as the card writes it: inside a left-to-right isolate.
String _iso(String text) => '\u2066$text\u2069';

RetentionRateDto _rate(int eligible, int retained) =>
    RetentionRateDto(eligible: eligible, retained: retained);

const _none = RetentionRateDto(eligible: 0, retained: 0);

final _stats = AdminRetentionDto(
  today: '2026-09-29',
  weeks: const [
    RetentionWeekDto(
      weekStart: '2026-09-28',
      complete: false,
      activeUsers: 11,
      active3Plus: 2,
      leagueActive: 6,
      leagueActive3Plus: 2,
      leagueMembers: 7,
      leagueReturned: null,
    ),
    RetentionWeekDto(
      weekStart: '2026-09-21',
      complete: true,
      activeUsers: 20,
      active3Plus: 5,
      leagueActive: 10,
      leagueActive3Plus: 4,
      leagueMembers: 12,
      leagueReturned: null,
    ),
    RetentionWeekDto(
      weekStart: '2026-09-14',
      complete: true,
      activeUsers: 16,
      active3Plus: 4,
      leagueActive: 8,
      leagueActive3Plus: 3,
      leagueMembers: 10,
      leagueReturned: 7,
    ),
  ],
  cohorts: [
    const RetentionCohortDto(
      weekStart: '2026-09-28',
      users: 3,
      day1: _none,
      day7: _none,
      day14: _none,
      week4: _none,
    ),
    RetentionCohortDto(
      weekStart: '2026-09-21',
      users: 8,
      day1: _rate(8, 4),
      day7: _rate(2, 1),
      day14: _none,
      week4: _none,
    ),
    RetentionCohortDto(
      weekStart: '2026-09-14',
      users: 10,
      day1: _rate(10, 6),
      day7: _rate(10, 3),
      day14: _rate(3, 1),
      week4: _none,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Future<AdminRetentionDto> Function() read,
) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [adminRetentionProvider.overrideWith((ref) => read())],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: SingleChildScrollView(child: AdminRetentionCard()),
        ),
      ),
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('leads with this week, last week and day seven', (tester) async {
    await _pump(tester, () async => _stats);

    expect(_text(tester, 'admin.retention.thisWeek'), '11');
    // The first complete week (21/9): 5 of 20 on three days or more.
    expect(_text(tester, 'admin.retention.threePlus'), _iso('25%'));
    // Day seven pooled over the cohorts that could be judged: 4 of 12.
    expect(_text(tester, 'admin.retention.day7'), _iso('33%'));
  });

  testWidgets('a row per week; league seats read once known', (tester) async {
    await _pump(tester, () async => _stats);

    expect(_text(tester, 'admin.retention.week.2026-09-21.active'), '20');
    expect(
      _text(tester, 'admin.retention.week.2026-09-21.threePlus'),
      _iso('25%'),
    );
    expect(
      _text(tester, 'admin.retention.week.2026-09-21.league'),
      _iso('40%'),
    );
    expect(_text(tester, 'admin.retention.week.2026-09-21.returned'), '—');
    expect(
      _text(tester, 'admin.retention.week.2026-09-14.returned'),
      _iso('70%'),
    );
    expect(find.text(_iso('7/10')), findsOneWidget);
    expect(find.text('جارٍ'), findsNWidgets(2));
  });

  testWidgets('a cohort shows a dash until its day has come', (tester) async {
    await _pump(tester, () async => _stats);

    expect(_text(tester, 'admin.retention.cohort.2026-09-21.users'), '8');
    expect(
      _text(tester, 'admin.retention.cohort.2026-09-21.day1'),
      _iso('50%'),
    );
    expect(_text(tester, 'admin.retention.cohort.2026-09-21.day14'), '—');
    expect(
      _text(tester, 'admin.retention.cohort.2026-09-14.day14'),
      _iso('33%'),
    );
    expect(find.text(_iso('1/3')), findsOneWidget);
    expect(_text(tester, 'admin.retention.cohort.2026-09-28.day1'), '—');
  });

  testWidgets('a quiet window says so instead of zeros', (tester) async {
    await _pump(
      tester,
      () async => const AdminRetentionDto(
        today: '2026-09-29',
        weeks: [
          RetentionWeekDto(
            weekStart: '2026-09-28',
            complete: false,
            activeUsers: 0,
            active3Plus: 0,
            leagueActive: 0,
            leagueActive3Plus: 0,
            leagueMembers: 0,
            leagueReturned: null,
          ),
        ],
        cohorts: [],
      ),
    );

    expect(find.byKey(const Key('admin.retention.empty')), findsOneWidget);
    expect(find.byKey(const Key('admin.retention.thisWeek')), findsNothing);
  });

  testWidgets('a failed read is said, not spun', (tester) async {
    await _pump(
      tester,
      () async => throw const AppError.transient('net.down', 'offline'),
    );

    expect(find.byKey(const Key('admin.retention.error')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
