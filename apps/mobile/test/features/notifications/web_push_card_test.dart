/// The home page's push card for the web build, through the real card with
/// a fake browser: on an iPhone in a tab it says how to add the app to the
/// home screen; where pushes can be shown it asks from the tap and then
/// registers the browser; it says what happened; it is never shown off the
/// web or once the player answered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/notifications/web_push_platform.dart';
import 'package:mobile/features/notifications/web_push_card.dart';

final class _Browser implements WebPushPlatform {
  _Browser({
    this.isWeb = true,
    this.isIos = false,
    this.isInstalled = false,
    this.isSupported = true,
    this.permission = 'default',
    this.answer = 'granted',
  });

  @override
  final bool isWeb;

  @override
  final bool isIos;

  @override
  final bool isInstalled;

  @override
  final bool isSupported;

  @override
  String permission;

  final String answer;
  int asked = 0;

  @override
  Future<String> requestPermission() async {
    asked++;
    permission = answer;
    return answer;
  }

  @override
  String get workerPath => '/nukhbaa/push/firebase-messaging-sw.js';

  @override
  String? launchLink() => null;
}

Future<List<int>> _pump(
  WidgetTester tester,
  _Browser browser, {
  bool registers = true,
}) async {
  final List<int> registered = <int>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        webPushPlatformProvider.overrideWithValue(browser),
        webPushRegistrarProvider.overrideWithValue(() async {
          registered.add(1);
          return registers;
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: WebPushCard())),
    ),
  );
  return registered;
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('what the browser is offered', () {
    test('nothing off the web', () {
      expect(webPushOfferFor(_Browser(isWeb: false)), WebPushOffer.none);
    });

    test('an iPhone in a tab is told to add the app first', () {
      expect(
        webPushOfferFor(_Browser(isIos: true, isSupported: false)),
        WebPushOffer.install,
      );
    });

    test('an installed iPhone that can show pushes is asked', () {
      expect(
        webPushOfferFor(_Browser(isIos: true, isInstalled: true)),
        WebPushOffer.enable,
      );
    });

    test('an answered or unable browser is left alone', () {
      expect(
        webPushOfferFor(_Browser(permission: 'granted')),
        WebPushOffer.none,
      );
      expect(
        webPushOfferFor(_Browser(permission: 'denied')),
        WebPushOffer.none,
      );
      expect(webPushOfferFor(_Browser(isSupported: false)), WebPushOffer.none);
    });
  });

  testWidgets('turning pushes on asks, registers and says so', (tester) async {
    final _Browser browser = _Browser();
    final List<int> registered = await _pump(tester, browser);

    await tester.tap(find.byKey(const Key('home.webPush.enable')));
    await tester.pump();

    expect(browser.asked, 1);
    expect(registered, hasLength(1));
    expect(
      _text(tester, 'home.webPush.outcome'),
      'ستصلك الإشعارات على هذا الجهاز.',
    );
  });

  testWidgets('a refusal registers nothing and says where to allow', (
    tester,
  ) async {
    final List<int> registered = await _pump(
      tester,
      _Browser(answer: 'denied'),
    );

    await tester.tap(find.byKey(const Key('home.webPush.enable')));
    await tester.pump();

    expect(registered, isEmpty);
    expect(_text(tester, 'home.webPush.outcome'), contains('إعدادات المتصفح'));
  });

  testWidgets('a failed registration says to try later', (tester) async {
    await _pump(tester, _Browser(), registers: false);

    await tester.tap(find.byKey(const Key('home.webPush.enable')));
    await tester.pump();

    expect(_text(tester, 'home.webPush.outcome'), contains('حاول لاحقاً'));
  });

  testWidgets('an iPhone in a tab is told how to add the app', (tester) async {
    await _pump(tester, _Browser(isIos: true, isSupported: false));

    expect(
      _text(tester, 'home.webPush.message'),
      contains('إضافة إلى الشاشة الرئيسية'),
    );
    expect(find.byKey(const Key('home.webPush.enable')), findsNothing);
  });

  testWidgets('later hides the card', (tester) async {
    await _pump(tester, _Browser());

    await tester.tap(find.byKey(const Key('home.webPush.later')));
    await tester.pump();

    expect(find.byKey(const Key('home.webPush')), findsNothing);
  });

  testWidgets('off the web there is no card', (tester) async {
    await _pump(tester, _Browser(isWeb: false));

    expect(find.byKey(const Key('home.webPush')), findsNothing);
  });
}
