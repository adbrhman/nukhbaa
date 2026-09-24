import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/features/competition/team_catalog_index.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/features/notifications/notifications_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';
import '../../support/current_month_fixtures_harness.dart';

/// Larger system text on the home screen, through the real [HomeScreen]:
/// the brand header and the overview card's title row overflowed at x2.0
/// (95px and 24px in the text-scale probe). Both now give way inside
/// their row; at normal size nothing moves.
const List<double> _scales = <double>[1.0, 1.3, 2.0];

void main() {
  for (final double scale in _scales) {
    testWidgets('home fits its rows at x$scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 7200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final auth = buildAuthHarness((request) async {
        if (request.url.path == '/me/daily-challenge') {
          return http.Response(
            jsonEncode(
              const MyDailyChallengeDto(
                day: '2026-09-23',
                total: 0,
                predicted: 0,
                complete: false,
              ).toJson(),
            ),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/me/streak') {
          return http.Response(
            jsonEncode(const MyStreakDto(current: 0, longest: 0).toJson()),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url.path}',
        );
      });
      addTearDown(auth.dispose);

      final overrides = <Override>[
        ...auth.overrides,
        currentMonthFixturesProvider.overrideWithValue(
          AsyncData<List<CurrentMonthFixtureItemDto>>([sampleFeedItem]),
        ),
        teamCatalogByIdProvider.overrideWithValue(null),
        activeSeasonsProvider.overrideWithValue(
          AsyncData<List<ActiveSeasonDto>>([
            const ActiveSeasonDto(
              competitionId: 'c-1',
              competitionName: 'الدوري السعودي',
              seasonId: 's-1',
              seasonLabel: '2026/27',
              startAt: '2026-09-01T00:00:00.000Z',
              endAt: '2026-10-01T00:00:00.000Z',
            ),
          ]),
        ),
        myFixturePredictionsByFixtureProvider.overrideWithValue(
          const AsyncData<Map<String, FixturePredictionDto>>({}),
        ),
        unreadCountProvider.overrideWithValue(const AsyncData<int>(0)),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          retry: (retryCount, error) => null,
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child ?? const SizedBox.shrink(),
            ),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('ar'),
            home: HomeScreen(
              user: const AuthenticatedUserDto(
                userId: 'u-1',
                role: 'user',
                status: 'active',
                displayName: 'عبدالرحمن',
              ),
              onOpenMatches: () {},
              onOpenAccount: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('home.brand')), findsOneWidget);
      expect(find.text('لوحة النخبة'), findsOneWidget);
    });
  }
}
