/// The player's chat with Nukhbaa support (migration 0187, script 166),
/// through the real [SupportChatScreen], [SupportApi] and [ApiTransport]
/// against a fake of the server's routes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/features/support/support_chat_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';
import 'support_fake_server.dart';

Future<List<Uri>> _pump(
  WidgetTester tester,
  FakeSupportServer server, {
  double textScale = 1,
  Size size = const Size(1080, 2400),
  bool mailOpens = true,
}) async {
  final List<Uri> opened = <Uri>[];
  final AuthHarness harness = buildAuthHarness(server.handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        notificationLinkOpenerProvider.overrideWithValue((Uri uri) async {
          opened.add(uri);
          return mailOpens;
        }),
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
        home: const SupportChatScreen(pollEvery: Duration(seconds: 2)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('one name, marked official; an empty chat says how it works', (
    tester,
  ) async {
    await _pump(tester, FakeSupportServer());

    expect(find.text('دعم نُخبة'), findsOneWidget);
    expect(find.byKey(const Key('support.official')), findsOneWidget);
    expect(find.byKey(const Key('support.empty')), findsOneWidget);
    expect(find.textContaining('واتساب'), findsNothing);
    // The send button wakes only once something is typed.
    final IconButton send = tester.widget(
      find.byKey(const Key('support.send')),
    );
    expect(send.onPressed, isNull);
  });

  testWidgets('a message goes to the server and shows as sent', (tester) async {
    final FakeSupportServer server = FakeSupportServer();
    await _pump(tester, server);

    await tester.enterText(
      find.byKey(const Key('support.input')),
      '  التطبيق لا يحفظ توقعي  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('support.send')));
    await tester.pumpAndSettle();

    expect(server.calls, contains('POST /me/support/messages'));
    expect(server.messages.single['body'], 'التطبيق لا يحفظ توقعي');
    expect(find.text('التطبيق لا يحفظ توقعي'), findsOneWidget);
    expect(find.byKey(const Key('support.status.sent')), findsOneWidget);
    expect(find.byKey(const Key('support.empty')), findsNothing);
    final TextField input = tester.widget(
      find.byKey(const Key('support.input')),
    );
    expect(input.controller!.text, isEmpty);
  });

  testWidgets('the player on the right, support on the left, read marks', (
    tester,
  ) async {
    final FakeSupportServer server = FakeSupportServer()
      ..add('player', 'سؤالي', read: true)
      ..add('support', 'جواب الدعم');
    await _pump(tester, server);

    final double mine = tester.getCenter(find.text('سؤالي')).dx;
    final double theirs = tester.getCenter(find.text('جواب الدعم')).dx;
    expect(
      mine,
      greaterThan(theirs),
      reason: 'RTL: the player is on the right',
    );
    expect(find.byKey(const Key('support.status.read')), findsOneWidget);
    // The answer on screen is marked read on the server.
    expect(server.calls, contains('POST /me/support/read'));
    expect(server.messages.last['read_at'], isNotNull);
  });

  testWidgets('a refused send stays with its reason and can be sent again', (
    tester,
  ) async {
    final FakeSupportServer server = FakeSupportServer()
      ..failNextSend = (
        429,
        'request.rate_limited',
        'طلبات كثيرة خلال وقت قصير. انتظر قليلًا ثم حاول مرة أخرى.',
      );
    await _pump(tester, server);

    await tester.enterText(find.byKey(const Key('support.input')), 'سؤال');
    await tester.pump();
    await tester.tap(find.byKey(const Key('support.send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('support.status.failed')), findsOneWidget);
    expect(find.byKey(const Key('support.resend')), findsOneWidget);
    expect(server.messages, isEmpty);

    await tester.tap(find.byKey(const Key('support.resend')));
    await tester.pumpAndSettle();

    expect(server.messages.single['body'], 'سؤال');
    expect(find.byKey(const Key('support.status.failed')), findsNothing);
    expect(find.byKey(const Key('support.status.sent')), findsOneWidget);
  });

  testWidgets('a new answer arrives while the chat is open', (tester) async {
    final FakeSupportServer server = FakeSupportServer()
      ..add('player', 'سؤالي');
    await _pump(tester, server);
    expect(find.text('وصل الرد'), findsNothing);

    server.add('support', 'وصل الرد');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('وصل الرد'), findsOneWidget);
    expect(server.messages.last['read_at'], isNotNull);
  });

  testWidgets('a lost connection is said, and goes once it is back', (
    tester,
  ) async {
    final FakeSupportServer server = FakeSupportServer()..add('player', 'س');
    await _pump(tester, server);

    server.readsFail = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support.offline')), findsOneWidget);
    expect(find.text('س'), findsOneWidget);

    server.readsFail = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support.offline')), findsNothing);
  });

  testWidgets('older messages load before the oldest one shown', (
    tester,
  ) async {
    final FakeSupportServer server = FakeSupportServer();
    for (int i = 1; i <= 32; i++) {
      server.add('player', 'رسالة $i', read: true);
    }
    await _pump(tester, server);
    expect(find.text('رسالة 1', skipOffstage: false), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('support.older')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('support.older')));
    await tester.pumpAndSettle();

    expect(server.calls.last, 'GET /me/support/messages?before=3');
    expect(find.text('رسالة 1', skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('support.older')), findsNothing);
  });

  testWidgets('a closed conversation says a new message reopens it', (
    tester,
  ) async {
    final FakeSupportServer server = FakeSupportServer()
      ..add('player', 'س', read: true)
      ..add('support', 'ج');
    server.status = 'closed';
    await _pump(tester, server);

    expect(find.byKey(const Key('support.closed')), findsOneWidget);
  });

  testWidgets('a failed first read offers a retry and the e-mail', (
    tester,
  ) async {
    final FakeSupportServer server = FakeSupportServer()..readsFail = true;
    final List<Uri> opened = await _pump(tester, server);

    expect(find.byKey(const Key('support.loadFailed')), findsOneWidget);
    await tester.tap(find.byKey(const Key('support.email')));
    await tester.pumpAndSettle();
    expect(opened.single.scheme, 'mailto');
    expect(opened.single.path, 'nukhbaa.app@gmail.com');

    server
      ..readsFail = false
      ..add('support', 'أهلًا');
    await tester.tap(find.byKey(const Key('support.retry')));
    await tester.pumpAndSettle();
    expect(find.text('أهلًا'), findsOneWidget);
  });

  testWidgets('the chat holds at text x2 on a 360px phone', (tester) async {
    final FakeSupportServer server = FakeSupportServer()
      ..add('player', 'سؤال طويل ${'كلمة ' * 40}', read: true)
      ..add('support', 'جواب طويل ${'كلمة ' * 40}');
    await _pump(tester, server, textScale: 2, size: const Size(360, 800));

    expect(find.byKey(const Key('support.title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
