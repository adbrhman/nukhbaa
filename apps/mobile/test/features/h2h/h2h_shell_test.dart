/// The head-to-head tab inside the real shell: its "go to the matches"
/// button switches the shell to the matches tab, the same way the home
/// screen's shortcut does.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/session/session_scope.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/theme/theme_controller.dart';
import 'package:mobile/core/ui/app_tab_header.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/h2h/h2h_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const MyH2hLeagueDto _league = MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-11-01',
  startsOn: '2026-11-01',
  isPilot: false,
  division: 2,
  groupIndex: 0,
  myRank: 1,
  promotionZone: 2,
  relegationZone: 2,
  daysLeft: 20,
  standings: <H2hStandingDto>[
    H2hStandingDto(
      rank: 1,
      userId: 'u-1',
      displayName: 'سامي',
      played: 0,
      won: 0,
      drawn: 0,
      lost: 0,
      leaguePoints: 0,
      pointsFor: 0,
      exactCount: 0,
      form: <String>[],
      isMe: true,
    ),
  ],
  rounds: <H2hRoundViewDto>[
    H2hRoundViewDto(
      round: 1,
      day: '2026-11-04',
      status: 'open',
      fixtureCount: 8,
      opponentUserId: 'u-2',
      opponentName: 'نورة',
    ),
  ],
);

/// Endless motion (a skeleton's shimmer) never settles; what was pumped is
/// enough.
Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  } on FlutterError {
    // Still moving: carry on.
  }
}

void main() {
  testWidgets('"go to the matches" opens the matches tab', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final AuthHarness harness = buildAuthHarness((http.Request request) async {
      if (request.url.path == '/me/h2h-league') {
        return http.Response(
          jsonEncode(_league.toJson()),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return okMe(sampleUser);
    }, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      SessionScope(
        overrides: <Override>[
          ...harness.overrides,
          themePreferenceStoreProvider.overrideWithValue(
            InMemoryThemePreferenceStore(ThemeMode.dark),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const SessionGate(),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const Key('nav.item.h2h')));
    await _settle(tester);
    expect(find.byType(H2hScreen).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const Key('h2h.goToMatches')));
    await _settle(tester);

    // The matches tab is the one on screen now.
    expect(
      find
          .descendant(
            of: find.byType(CurrentMonthFixturesScreen),
            matching: find.byType(AppTabHeader),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('h2h.goToMatches')).hitTestable(),
      findsNothing,
    );
  });
}
