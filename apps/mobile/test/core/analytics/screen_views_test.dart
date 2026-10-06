/// Screen opens (migration 0093) through the real observer, the real
/// screens and the real shell: a pushed screen and a bottom sheet are
/// counted once under their names, a dialog is not, the tabs are counted as
/// the player switches to them, and a failed report keeps its counts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/analytics/screen_views.dart';
import 'package:mobile/core/session/session_scope.dart';
import 'package:mobile/features/auth/account_settings_screen.dart';
import 'package:mobile/features/auth/rules_screen.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/duels/duels_screen.dart';
import 'package:mobile/features/gamification/insights_screen.dart';
import 'package:mobile/features/gamification/my_badges_screen.dart';
import 'package:mobile/features/groups/my_groups_screen.dart';
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

class _Sheet extends StatelessWidget implements NamedScreen {
  const _Sheet();

  @override
  String get screenName => ScreenNames.duelAccept;

  @override
  Widget build(BuildContext context) => const SizedBox(height: 200);
}

/// A plain app whose navigator counts into [log], with a button that runs
/// [open] from inside it.
Future<void> _pumpLauncher(
  WidgetTester tester,
  ScreenViewLog log,
  void Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      navigatorObservers: <NavigatorObserver>[ScreenViewObserver(log)],
      home: Builder(
        builder: (BuildContext context) => Center(
          child: TextButton(
            key: const Key('open'),
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ScreenViewLog', () {
    test('counts known names only, up to the server limit', () {
      final ScreenViewLog log = ScreenViewLog()
        ..record(ScreenNames.duels)
        ..record(ScreenNames.duels)
        ..record('not_a_screen');
      for (int i = 0; i < ScreenViewLog.maxOpensPerScreen + 5; i++) {
        log.record(ScreenNames.home);
      }

      expect(log.pending, <String, int>{
        'duels': 2,
        'home': ScreenViewLog.maxOpensPerScreen,
      });
    });

    test('drain empties the log and restore puts a failed report back', () {
      final ScreenViewLog log = ScreenViewLog()..record(ScreenNames.badges);

      final Map<String, int> sent = log.drain();
      log.record(ScreenNames.badges);
      log.restore(sent);

      expect(sent, <String, int>{'badges': 1});
      expect(log.pending, <String, int>{'badges': 2});
    });
  });

  group('ScreenViewObserver', () {
    testWidgets('a pushed screen is counted once under its name', (
      tester,
    ) async {
      final ScreenViewLog log = ScreenViewLog();
      await _pumpLauncher(
        tester,
        log,
        (BuildContext context) => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const RulesScreen()),
        ),
      );

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(find.byType(RulesScreen), findsOneWidget);
      expect(log.pending, <String, int>{'rules': 1});
    });

    testWidgets('a bottom sheet is counted under its content', (tester) async {
      final ScreenViewLog log = ScreenViewLog();
      await _pumpLauncher(
        tester,
        log,
        (BuildContext context) => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const _Sheet(),
        ),
      );

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(log.pending, <String, int>{'duel_accept': 1});
    });

    testWidgets('a dialog counts nothing', (tester) async {
      final ScreenViewLog log = ScreenViewLog();
      await _pumpLauncher(
        tester,
        log,
        (BuildContext context) => showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('x')),
        ),
      );

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(log.pending, isEmpty);
    });
  });

  test('the feature screens carry names the server knows', () {
    final Map<Widget, String> screens = <Widget, String>{
      const RulesScreen(): 'rules',
      const AccountSettingsScreen(): 'settings',
      const NotificationsScreen(): 'notifications',
      const DuelsScreen(): 'duels',
      const MyGroupsScreen(): 'groups',
      const MyBadgesScreen(): 'badges',
      const InsightsScreen(): 'insights',
    };
    for (final MapEntry<Widget, String> e in screens.entries) {
      expect(e.key, isA<NamedScreen>(), reason: e.value);
      expect((e.key as NamedScreen).screenName, e.value);
      expect(ScreenNames.all, contains(e.value));
    }
  });

  group('ScreenViewReporter', () {
    test('a kept report empties the log', () async {
      final ScreenViewLog log = ScreenViewLog()..record(ScreenNames.duels);
      final List<Map<String, int>> sent = <Map<String, int>>[];
      final ScreenViewReporter reporter = ScreenViewReporter(
        log: log,
        send: (Map<String, int> opens) async {
          sent.add(opens);
          return true;
        },
      );

      await reporter.flush();
      await reporter.flush();

      expect(sent, <Map<String, int>>[
        <String, int>{'duels': 1},
      ]);
      expect(log.pending, isEmpty);
    });

    test('a failed report is kept for the next one', () async {
      final ScreenViewLog log = ScreenViewLog()..record(ScreenNames.duels);
      final ScreenViewReporter reporter = ScreenViewReporter(
        log: log,
        send: (Map<String, int> opens) async => throw StateError('offline'),
      );

      await reporter.flush();

      expect(log.pending, <String, int>{'duels': 1});
    });

    test('a local build never sends', () async {
      final ScreenViewLog log = ScreenViewLog()..record(ScreenNames.duels);
      int calls = 0;
      final ScreenViewReporter reporter = ScreenViewReporter(
        log: log,
        enabled: false,
        send: (Map<String, int> opens) async {
          calls++;
          return true;
        },
      );

      await reporter.flush();

      expect(calls, 0);
      expect(log.pending, <String, int>{'duels': 1});
    });
  });

  testWidgets('the shell counts the home tab and each tab switched to', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = buildAuthHarness(
      (http.Request request) async => okMe(sampleUser),
      seedToken: 'saved-jwt',
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      SessionScope(
        overrides: harness.overrides,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const SessionGate(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ScreenViewLog log = ProviderScope.containerOf(
      tester.element(find.byType(SessionGate)),
    ).read(screenViewLogProvider);
    expect(log.pending, <String, int>{'home': 1});

    await tester.tap(find.byKey(const Key('nav.item.leaders')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('nav.item.leaders')));
    await tester.pump();

    expect(log.pending, <String, int>{'home': 1, 'leaderboard': 1});
  });
}
