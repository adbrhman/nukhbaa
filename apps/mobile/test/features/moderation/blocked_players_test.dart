/// Script 225: reporting and blocking a player from the board. The report
/// goes to the support chat; the block hides the name on this phone, is
/// kept, and is lifted from the sheet or from the settings list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leaderboards/widgets/leaderboard_board.dart';
import 'package:mobile/features/moderation/blocked_players.dart';
import 'package:mobile/features/moderation/blocked_players_screen.dart';
import 'package:mobile/features/moderation/player_actions.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';
import '../support/support_fake_server.dart';

BoardEntry _entry(String id, int rank, int points) => BoardEntry(
  participantId: id,
  rank: rank,
  displayName: id,
  points: points,
  pointsLabel: '$points',
  matchesCount: 4,
);

final List<BoardEntry> _board = <BoardEntry>[
  _entry('a', 1, 20),
  _entry('b', 2, 15),
  _entry('c', 3, 12),
  _entry('d', 4, 10),
  _entry('e', 5, 8),
];

Future<void> _pump(
  WidgetTester tester, {
  required InMemoryBlockedPlayersStore store,
  FakeSupportServer? server,
  Widget? home,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final AuthHarness harness = buildAuthHarness(
    (server ?? FakeSupportServer()).handle,
    seedToken: 'jwt',
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        blockedPlayersStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home:
            home ??
            Scaffold(
              body: LeaderboardBoard(
                entries: _board,
                keyPrefix: 't',
                myParticipantId: 'd',
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _nameOf(WidgetTester tester, String id) =>
    tester.widget<Text>(find.byKey(Key('t.participant.$id'))).data ?? '';

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  test('a block key ignores case and extra spaces', () {
    expect(blockKeyOf('  Ali   HASSAN '), 'ali hassan');
    expect(blockKeyOf('محمد  العماري'), 'محمد العماري');
  });

  test('the report says who, which participant and why', () {
    final String text = playerReportMessage(
      displayName: 'Ali Hassan',
      participantId: 'p-1',
      reason: playerReportReasons.first,
    );
    expect(text, contains('Ali Hassan'));
    expect(text, contains('p-1'));
    expect(text, contains(playerReportReasons.first));
    expect(text.length, lessThan(2000));
    expect(text, text.trim());
  });

  test('blocking is kept, restored by a new session and lifted', () async {
    final InMemoryBlockedPlayersStore store = InMemoryBlockedPlayersStore();
    final ProviderContainer first = ProviderContainer(
      overrides: [blockedPlayersStoreProvider.overrideWithValue(store)],
    );
    addTearDown(first.dispose);
    first.read(blockedPlayersProvider);
    await first.read(blockedPlayersProvider.notifier).block('  Ali   Hassan ');
    expect(first.read(blockedPlayersProvider), <String, String>{
      'ali hassan': 'Ali Hassan',
    });
    expect(store.blocked, <String, String>{'ali hassan': 'Ali Hassan'});

    final ProviderContainer second = ProviderContainer(
      overrides: [blockedPlayersStoreProvider.overrideWithValue(store)],
    );
    addTearDown(second.dispose);
    second.read(blockedPlayersProvider);
    await Future<void>.delayed(Duration.zero);
    expect(second.read(blockedPlayersProvider).keys, <String>['ali hassan']);

    await second.read(blockedPlayersProvider.notifier).unblock('ali hassan');
    expect(second.read(blockedPlayersProvider), isEmpty);
    expect(store.blocked, isEmpty);
  });

  testWidgets('every line but the viewer\'s own has the menu', (tester) async {
    await _pump(tester, store: InMemoryBlockedPlayersStore());

    expect(find.byKey(const Key('player.menu.a')), findsOneWidget);
    expect(find.byKey(const Key('player.menu.e')), findsOneWidget);
    expect(find.byKey(const Key('player.menu.d')), findsNothing);
  });

  testWidgets('blocking hides the name and is kept', (tester) async {
    final InMemoryBlockedPlayersStore store = InMemoryBlockedPlayersStore();
    await _pump(tester, store: store);
    expect(_nameOf(tester, 'e'), 'e');

    await _tap(tester, 'player.menu.e');
    expect(
      tester.widget<Text>(find.byKey(const Key('playerActions.name'))).data,
      'e',
    );
    await _tap(tester, 'playerActions.block');

    expect(_nameOf(tester, 'e'), blockedPlayerLabel);
    expect(_nameOf(tester, 'b'), 'b');
    expect(store.blocked, <String, String>{'e': 'e'});
    expect(find.text(playerBlockedMessage), findsOneWidget);
  });

  testWidgets('a blocked podium place is hidden too, and can be lifted', (
    tester,
  ) async {
    final InMemoryBlockedPlayersStore store = InMemoryBlockedPlayersStore(
      <String, String>{'a': 'a'},
    );
    await _pump(tester, store: store);
    expect(_nameOf(tester, 'a'), blockedPlayerLabel);

    await _tap(tester, 'player.menu.a');
    expect(find.byKey(const Key('playerActions.block')), findsNothing);
    await _tap(tester, 'playerActions.unblock');

    expect(_nameOf(tester, 'a'), 'a');
    expect(store.blocked, isEmpty);
  });

  testWidgets('a report reaches the support chat with the reason', (
    tester,
  ) async {
    final FakeSupportServer server = FakeSupportServer();
    await _pump(tester, store: InMemoryBlockedPlayersStore(), server: server);

    await _tap(tester, 'player.menu.e');
    await _tap(tester, 'playerActions.report');
    await _tap(tester, 'playerReport.reason.0');

    expect(server.messages, hasLength(1));
    final String body = server.messages.single['body']! as String;
    expect(body, contains('الاسم: e'));
    expect(body, contains('المعرّف: e'));
    expect(body, contains(playerReportReasons.first));
    expect(find.text(reportSentMessage), findsOneWidget);
    // A report is not a block.
    expect(_nameOf(tester, 'e'), 'e');
  });

  testWidgets('closing the reason sheet sends nothing', (tester) async {
    final FakeSupportServer server = FakeSupportServer();
    await _pump(tester, store: InMemoryBlockedPlayersStore(), server: server);

    await _tap(tester, 'player.menu.e');
    await _tap(tester, 'playerActions.report');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(server.messages, isEmpty);
  });

  testWidgets('the settings list shows the blocked and lifts a block', (
    tester,
  ) async {
    final InMemoryBlockedPlayersStore store = InMemoryBlockedPlayersStore(
      <String, String>{'ali hassan': 'Ali Hassan'},
    );
    await _pump(tester, store: store, home: const BlockedPlayersScreen());
    expect(find.text('Ali Hassan'), findsOneWidget);

    await _tap(tester, 'blocked.unblock.ali hassan');

    expect(find.byKey(const Key('blocked.empty')), findsOneWidget);
    expect(store.blocked, isEmpty);
  });
}
