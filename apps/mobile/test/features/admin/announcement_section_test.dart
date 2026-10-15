/// The announcement screen through the real `AdminApi` over a faked socket
/// (audit M-14): nothing is sent before the admin confirms, a retry of the
/// same message carries the same `request_id`, and the count reads in
/// Arabic.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/announcement_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart';

const String _path = '/admin/announcements';

Future<AdminHarness> _open(
  WidgetTester tester,
  Future<http.Response> Function(http.Request request) handler,
) async {
  final AdminHarness harness = buildAdminHarness(handler);
  addTearDown(harness.dispose);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const Scaffold(body: AnnouncementSection()),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('admin.announcement.titleField')),
    'تنبيه',
  );
  await tester.enterText(
    find.byKey(const Key('admin.announcement.bodyField')),
    'مباريات الجمعة تبدأ مبكرًا',
  );
  await tester.pumpAndSettle();
  return harness;
}

List<Map<String, Object?>> _sent(AdminHarness harness) =>
    <Map<String, Object?>>[
      for (final CapturedRequest c in harness.captured)
        if (c.request.url.path == _path)
          jsonDecode(c.request.body) as Map<String, Object?>,
    ];

Future<void> _sendAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('admin.announcement.sendButton')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('admin.announcement.confirm')), findsOneWidget);
  await tester.tap(find.byKey(const Key('admin.announcement.confirmSend')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nothing is sent until the admin confirms', (tester) async {
    final AdminHarness harness = await _open(
      tester,
      (_) async =>
          okJsonObject(<String, Object?>{'schema_version': 1, 'recipients': 3}),
    );

    await tester.tap(find.byKey(const Key('admin.announcement.sendButton')));
    await tester.pumpAndSettle();
    expect(find.text('مباريات الجمعة تبدأ مبكرًا'), findsWidgets);
    await tester.tap(find.byKey(const Key('admin.announcement.cancel')));
    await tester.pumpAndSettle();

    expect(_sent(harness), isEmpty);

    await _sendAndConfirm(tester);

    expect(_sent(harness), hasLength(1));
    expect(find.byKey(const Key('admin.announcement.sent')), findsOneWidget);
    expect(find.text('أُرسل الإشعار إلى 3 مستخدمين'), findsOneWidget);
  });

  testWidgets('a retry of the same message carries the same request id', (
    tester,
  ) async {
    var calls = 0;
    final AdminHarness harness = await _open(tester, (_) async {
      calls++;
      return calls == 1
          ? errorEnvelope(503, 'api_client.timeout', 'timeout')
          : okJsonObject(<String, Object?>{
              'schema_version': 1,
              'recipients': 0,
            });
    });

    await _sendAndConfirm(tester);
    await _sendAndConfirm(tester);

    final List<Map<String, Object?>> sent = _sent(harness);
    expect(sent, hasLength(2));
    final Object? id = sent.first['request_id'];
    expect(id, isA<String>());
    expect(sent.last['request_id'], id);
    expect(
      find.text('وصل هذا الإشعار من قبل، فلم يُرسل مرة أخرى.'),
      findsOneWidget,
    );
  });

  test('a request id is a version-4 UUID', () {
    final String id = newAnnouncementRequestId(Random(7));
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
        r'[0-9a-f]{12}$',
      ).hasMatch(id),
      isTrue,
      reason: id,
    );
  });
}
