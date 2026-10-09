import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/analytics/screen_views.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/features/competition/team_catalog_index.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/features/notifications/notifications_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';
import '../../support/current_month_fixtures_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

/// "توقعاتي" left the bottom bar for the head-to-head league: the home page
/// opens it, through the real [HomeScreen], as a pushed page with its own
/// back button, counted under its own screen name.
void main() {
  testWidgets('home opens my predictions and comes back', (tester) async {
    // Tall enough that the lazy ListView builds every card.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = buildAuthHarness((request) async {
      if (request.url.path == '/me/daily-challenge') {
        return _json(
          const MyDailyChallengeDto(
            day: '2026-09-23',
            total: 3,
            predicted: 1,
            complete: false,
          ).toJson(),
        );
      }
      if (request.url.path == '/me/streak') {
        return _json(const MyStreakDto(current: 0, longest: 0).toJson());
      }
      // Every list the history page reads is empty.
      return _json(const <Object?>[]);
    });
    addTearDown(auth.dispose);

    final overrides = <Override>[
      ...auth.overrides,
      currentMonthFixturesProvider.overrideWithValue(
        AsyncData<List<CurrentMonthFixtureItemDto>>([sampleFeedItem]),
      ),
      teamCatalogByIdProvider.overrideWithValue(null),
      activeSeasonsProvider.overrideWithValue(
        const AsyncData<List<ActiveSeasonDto>>(<ActiveSeasonDto>[]),
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

    final Finder card = find.byKey(const Key('home.myPredictions'));
    expect(card, findsOneWidget);
    // In the place the day's challenge held: after the matches, before it.
    expect(
      tester.getTopLeft(card).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('home.dailyChallenge'))).dy,
      ),
    );

    await tester.tap(card);
    await tester.pumpAndSettle();

    final Finder page = find.byType(PredictionHistoryScreen);
    expect(page, findsOneWidget);
    expect(find.byKey(const Key('history.title')), findsOneWidget);
    expect(
      (tester.widget(page) as NamedScreen).screenName,
      ScreenNames.predictions,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(card, findsOneWidget);
  });
}
