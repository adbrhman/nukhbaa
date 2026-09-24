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

/// The home page's reading order and how it reads aloud, through the real
/// [HomeScreen]: what to do now (the predictions still open) comes first,
/// then the matches they are about, then the day's challenge, then the
/// season overview; each match row is one spoken sentence.
void main() {
  testWidgets('home reads in the order of what to do', (tester) async {
    // Tall enough that the lazy ListView builds every card.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      final auth = buildAuthHarness((request) async {
        if (request.url.path == '/me/daily-challenge') {
          return http.Response(
            jsonEncode(
              const MyDailyChallengeDto(
                day: '2026-09-23',
                total: 3,
                predicted: 1,
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

      double top(Finder finder) => tester.getTopLeft(finder).dy;
      final double pending = top(
        find.byKey(const Key('home.pendingPredictions')),
      );
      final double match = top(find.byKey(const Key('home.highlight.f-1')));
      final double challenge = top(
        find.byKey(const Key('home.dailyChallenge')),
      );
      final double overview = top(find.text('لوحة النخبة'));
      expect(pending, lessThan(match), reason: 'the action leads');
      expect(match, lessThan(challenge));
      expect(challenge, lessThan(overview), reason: 'the overview is detail');

      expect(
        tester.getSemantics(find.text('Vs')).id,
        tester.getSemantics(find.byKey(const Key('home.highlight.f-1'))).id,
        reason: 'a match row is one node, read as one sentence',
      );
    } finally {
      handle.dispose();
    }
  });
}
