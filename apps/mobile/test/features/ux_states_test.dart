/// The main screens' loading and error states, through the real screens:
/// loading draws placeholders instead of a bare spinner, and a failed load
/// offers a retry that actually reloads.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/app_error_state.dart';
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/leaderboards/leaderboards_screen.dart';
import 'package:mobile/features/record/my_points_screen.dart';
import 'package:mobile/features/record/season_record_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

Widget _host(List<Override> overrides, Widget home) => ProviderScope(
  overrides: overrides,
  retry: (retryCount, error) => null,
  child: MaterialApp(
    theme: AppTheme.dark,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: home,
  ),
);

Future<void> _settleReads(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

Future<void> _tapRetry(WidgetTester tester, Type screen) async {
  final String retry = AppLocalizations.of(
    tester.element(find.byType(screen)),
  ).retry;
  await tester.tap(
    find.descendant(of: find.byType(AppErrorState), matching: find.text(retry)),
  );
  await _settleReads(tester);
}

void main() {
  testWidgets('my points: loading draws placeholders, not a spinner', (
    tester,
  ) async {
    final Completer<List<MySeasonRecordDto>> pending =
        Completer<List<MySeasonRecordDto>>();
    await tester.pumpWidget(
      _host(<Override>[
        mySeasonRecordsProvider.overrideWith((ref) => pending.future),
      ], const MyPointsScreen()),
    );
    await tester.pump();

    expect(find.byKey(const Key('myPoints.loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('my points: a failed load offers a retry that reloads', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(<Override>[
        mySeasonRecordsProvider.overrideWith((ref) async {
          calls++;
          if (calls == 1) {
            throw const AppError.transient('net.down', 'offline');
          }
          return const <MySeasonRecordDto>[];
        }),
      ], const MyPointsScreen()),
    );
    await _settleReads(tester);
    expect(find.byKey(const Key('myPoints.error')), findsOneWidget);

    await _tapRetry(tester, MyPointsScreen);

    expect(calls, 2);
    expect(find.byType(AppErrorState), findsNothing);
  });

  testWidgets('leaderboards: a failed load offers a retry that reloads', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(<Override>[
        activeSeasonsProvider.overrideWith((ref) async {
          calls++;
          if (calls == 1) {
            throw const AppError.transient('net.down', 'offline');
          }
          return const <ActiveSeasonDto>[];
        }),
        currentMonthFixturesProvider.overrideWith(
          (ref) async => const <CurrentMonthFixtureItemDto>[],
        ),
      ], const LeaderboardsScreen()),
    );
    await _settleReads(tester);
    expect(find.byKey(const Key('leaderboards.error')), findsOneWidget);

    await _tapRetry(tester, LeaderboardsScreen);

    expect(calls, 2);
    expect(find.byType(AppErrorState), findsNothing);
  });
}
