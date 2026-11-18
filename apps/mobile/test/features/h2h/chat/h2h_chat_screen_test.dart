/// The chat of the player's own head-to-head group (migration 0216, scripts
/// 281 and 282), through the real [H2hChatScreen], [H2hChatApi] and
/// [ApiTransport] against a fake of the server's routes. Reporting and
/// blocking are script 225's: a report reaches the support chat, a block is
/// kept on the phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/chat/h2h_chat_screen.dart';
import 'package:mobile/features/moderation/blocked_players.dart';
import 'package:mobile/features/moderation/player_actions.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../../support/auth_harness.dart';
import 'h2h_chat_fake_server.dart';

Future<InMemoryBlockedPlayersStore> _pump(
  WidgetTester tester,
  FakeH2hChatServer server, {
  double textScale = 1,
  Size size = const Size(1080, 2400),
  InMemoryBlockedPlayersStore? blocked,
}) async {
  final InMemoryBlockedPlayersStore store =
      blocked ?? InMemoryBlockedPlayersStore();
  final AuthHarness harness = buildAuthHarness(server.handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        blockedPlayersStoreProvider.overrideWithValue(store),
      ],
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
          child: child!,
        ),
        home: const H2hChatScreen(pollEvery: Duration(seconds: 2)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('the rules come first; accepting opens the chat', (tester) async {
    final FakeH2hChatServer server = FakeH2hChatServer(rulesAccepted: false)
      ..add('مرحبا بالجميع');
    await _pump(tester, server);

    expect(find.byKey(const Key('h2hChat.rules')), findsOneWidget);
    expect(find.byKey(const Key('h2hChat.input')), findsNothing);

    await tester.tap(find.byKey(const Key('h2hChat.accept')));
    await tester.pumpAndSettle();

    expect(server.calls, contains('POST /me/h2h-league/chat/rules'));
    expect(find.byKey(const Key('h2hChat.rules')), findsNothing);
    expect(find.byKey(const Key('h2hChat.input')), findsOneWidget);
    expect(find.text('مرحبا بالجميع'), findsOneWidget);
  });

  testWidgets('an empty chat invites the first message', (tester) async {
    await _pump(tester, FakeH2hChatServer());

    expect(find.byKey(const Key('h2hChat.empty')), findsOneWidget);
    expect(find.byKey(const Key('h2hChat.input')), findsOneWidget);
  });

  testWidgets('a player with no group has no chat', (tester) async {
    await _pump(tester, FakeH2hChatServer(hasGroup: false));

    expect(find.byKey(const Key('h2hChat.noGroup')), findsOneWidget);
    expect(find.byKey(const Key('h2hChat.input')), findsNothing);
  });

  testWidgets(
    'another player\'s message shows his name, one of mine does not',
    (tester) async {
      final FakeH2hChatServer server = FakeH2hChatServer()
        ..add('أهلًا من سالم')
        ..add('أهلًا بك', sender: FakeH2hChatServer.me);
      await _pump(tester, server);

      expect(find.text('أهلًا من سالم'), findsOneWidget);
      expect(find.text('سالم'), findsOneWidget);
      expect(find.text('أهلًا بك'), findsOneWidget);
      expect(find.text('أنا'), findsNothing);
      // Opening the chat marks it read.
      expect(server.calls, contains('POST /me/h2h-league/chat/read'));
    },
  );

  testWidgets('a message is sent and shown; the send button wakes on typing', (
    tester,
  ) async {
    final FakeH2hChatServer server = FakeH2hChatServer();
    await _pump(tester, server);

    final Finder send = find.byKey(const Key('h2hChat.send'));
    expect(tester.widget<IconButton>(send).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('h2hChat.input')),
      'مساء الخير',
    );
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(server.messages.single['body'], 'مساء الخير');
    expect(find.text('مساء الخير'), findsOneWidget);
    expect(find.byKey(const Key('h2hChat.empty')), findsNothing);
  });

  testWidgets('a muted player can read but not write', (tester) async {
    final FakeH2hChatServer server = FakeH2hChatServer(muted: true)
      ..add('رسالة قديمة');
    await _pump(tester, server);

    expect(find.byKey(const Key('h2hChat.muted')), findsOneWidget);
    expect(find.byKey(const Key('h2hChat.input')), findsNothing);
    expect(find.text('رسالة قديمة'), findsOneWidget);
  });

  testWidgets('a send refused for the rules brings the rules back', (
    tester,
  ) async {
    final FakeH2hChatServer server = FakeH2hChatServer();
    await _pump(tester, server);
    server.rulesAccepted = false;

    await tester.enterText(find.byKey(const Key('h2hChat.input')), 'مرحبا');
    await tester.pump();
    await tester.tap(find.byKey(const Key('h2hChat.send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('h2hChat.rules')), findsOneWidget);
    expect(server.messages, isEmpty);
  });

  testWidgets('a failed send can be sent again', (tester) async {
    final FakeH2hChatServer server = FakeH2hChatServer()
      ..failNextSend = (503, 'db.query_failed', 'down');
    await _pump(tester, server);

    await tester.enterText(find.byKey(const Key('h2hChat.input')), 'مرحبا');
    await tester.pump();
    await tester.tap(find.byKey(const Key('h2hChat.send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('h2hChat.resend')), findsOneWidget);
    expect(server.messages, isEmpty);

    await tester.tap(find.byKey(const Key('h2hChat.resend')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('h2hChat.resend')), findsNothing);
    expect(server.messages.single['body'], 'مرحبا');
  });

  testWidgets('new messages arrive while the screen is open', (tester) async {
    final FakeH2hChatServer server = FakeH2hChatServer()..add('الأولى');
    await _pump(tester, server);

    server.add('رسالة جديدة');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('رسالة جديدة'), findsOneWidget);
    expect(find.text('الأولى'), findsOneWidget);
    expect(server.calls, contains('GET /me/h2h-league/chat?after=1'));
  });

  testWidgets('blocking a player hides his messages from the chat', (
    tester,
  ) async {
    final FakeH2hChatServer server = FakeH2hChatServer()
      ..add('رسالة سالم')
      ..add(
        'رسالة فهد',
        sender: 'cccccccc-0000-4000-8000-000000000003',
        name: 'فهد',
      );
    final InMemoryBlockedPlayersStore store = await _pump(tester, server);

    await tester.longPress(find.text('رسالة سالم'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('h2hChat.menu.name')), findsOneWidget);
    await tester.tap(find.byKey(const Key('h2hChat.menu.block')));
    await tester.pumpAndSettle();

    expect(find.text('رسالة سالم'), findsNothing);
    expect(find.text('رسالة فهد'), findsOneWidget);
    expect(find.text(playerBlockedMessage), findsOneWidget);
    expect(store.blocked.keys, contains(blockKeyOf('سالم')));
  });

  testWidgets('a player blocked on this phone is already hidden', (
    tester,
  ) async {
    final FakeH2hChatServer server = FakeH2hChatServer()
      ..add('رسالة سالم')
      ..add(
        'رسالة فهد',
        sender: 'cccccccc-0000-4000-8000-000000000003',
        name: 'فهد',
      );
    await _pump(
      tester,
      server,
      blocked: InMemoryBlockedPlayersStore(<String, String>{
        blockKeyOf('سالم'): 'سالم',
      }),
    );

    expect(find.text('رسالة سالم'), findsNothing);
    expect(find.text('رسالة فهد'), findsOneWidget);
  });

  testWidgets('a report reaches the support chat with the message quoted', (
    tester,
  ) async {
    final FakeH2hChatServer server = FakeH2hChatServer()..add('كلام مسيء');
    await _pump(tester, server);

    await tester.longPress(find.text('كلام مسيء'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('h2hChat.menu.report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('h2hChat.reason.3')));
    await tester.pumpAndSettle();

    final String report = server.supportMessages.single;
    expect(report, contains('بلاغ عن رسالة في دردشة المجموعة'));
    expect(report, contains('الاسم: سالم'));
    expect(report, contains('رقم الرسالة: 1'));
    expect(report, contains('النص: كلام مسيء'));
    expect(report, contains('السبب: ${playerReportReasons[3]}'));
    expect(find.text(reportSentMessage), findsOneWidget);
  });

  testWidgets('a failed load says so and can be retried', (tester) async {
    final FakeH2hChatServer server = FakeH2hChatServer()..readsFail = true;
    await _pump(tester, server);

    expect(find.byKey(const Key('h2hChat.loadFailed')), findsOneWidget);
    expect(find.byKey(const Key('h2hChat.input')), findsNothing);
  });

  testWidgets('narrow, with large text, nothing overflows', (tester) async {
    final FakeH2hChatServer server = FakeH2hChatServer()
      ..add(
        'رسالة طويلة جدًا تتكرر كلماتها لتختبر التفاف النص داخل الفقاعة ' * 3,
      )
      ..add('قصيرة', sender: FakeH2hChatServer.me);
    await _pump(tester, server, textScale: 2, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rules page scrolls on a narrow screen with large text', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeH2hChatServer(rulesAccepted: false),
      textScale: 2,
      size: const Size(360, 640),
    );
    expect(find.byKey(const Key('h2hChat.accept')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
