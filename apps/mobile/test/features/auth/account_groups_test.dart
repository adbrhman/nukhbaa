/// Widget tests for the grouped [AccountScreen]: the rows sit under two
/// captions in reading order (what the player earned, the app), sign-out
/// stays last, and each figure of the profile card opens its
/// own detail page.
///
/// The real screen over the real [ApiTransport]; only the socket is faked
/// ([buildAuthHarness]'s `MockClient`), so every request the pages make
/// goes through the providers the app wires.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/account_screen.dart';
import 'package:mobile/features/gamification/insights_screen.dart';
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/features/record/my_points_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const AuthenticatedUserDto _player = AuthenticatedUserDto(
  userId: 'u-1',
  role: 'user',
  status: 'active',
  email: 'a@example.com',
  displayName: 'سامي',
);

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1080, 4000),
  double textScale = 1,
}) async {
  final AuthHarness harness = buildAuthHarness(
    (http.Request request) async => http.Response('not found', 404),
    seedToken: 'jwt',
  );
  addTearDown(harness.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: const AccountScreen(user: _player),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inside(String group, String row) =>
    find.descendant(of: find.byKey(Key(group)), matching: find.byKey(Key(row)));

double _top(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(Key(key))).dy;

void main() {
  testWidgets('two groups in reading order, sign-out last', (tester) async {
    await _pump(tester);

    for (final String row in <String>[
      'account.myPoints',
      'account.eliteCard',
      'account.badges',
      'account.insights',
    ]) {
      expect(_inside('account.group.progress', row), findsOneWidget);
    }
    // The invitations and the duels were removed (2026-10-26), and with
    // them the friends' group of rows.
    expect(find.byKey(const Key('account.invite')), findsNothing);
    expect(find.byKey(const Key('account.duels')), findsNothing);
    expect(find.byKey(const Key('account.group.friends')), findsNothing);
    expect(_inside('account.group.app', 'account.settings'), findsOneWidget);
    expect(
      _inside('account.group.app', 'account.darkModeToggle'),
      findsOneWidget,
    );
    expect(find.text('إنجازاتك'), findsOneWidget);
    expect(find.text('الأصدقاء'), findsNothing);
    expect(find.text('التطبيق'), findsOneWidget);

    final List<double> tops = <double>[
      _top(tester, 'account.group.progress'),
      _top(tester, 'account.group.app'),
      _top(tester, 'account.signOut'),
    ];
    expect(tops, orderedEquals(<double>[...tops]..sort()));
    // A player sees no admin row.
    expect(find.byKey(const Key('account.adminDashboard')), findsNothing);
  });

  testWidgets('the points figure opens the points page', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('account.stat.points.open')));
    await tester.pumpAndSettle();
    expect(find.byType(MyPointsScreen), findsOneWidget);
  });

  testWidgets('the accuracy figure opens the insights', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('account.stat.accuracy.open')));
    await tester.pumpAndSettle();
    expect(find.byType(InsightsScreen), findsOneWidget);
  });

  testWidgets('the matches figure opens the predictions', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('account.stat.matches.open')));
    await tester.pumpAndSettle();
    expect(find.byType(PredictionHistoryScreen), findsOneWidget);
  });

  testWidgets('holds at 360px and text x2', (tester) async {
    await _pump(tester, size: const Size(360, 4000), textScale: 2);

    expect(find.byKey(const Key('account.group.app')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
