/// Script 292: «وضع التطبيق» on the owners' page, through the real
/// providers and `AdminApi` over the auth harness's fake server: it shows
/// the mode, and changes it only with a reason. Also drawn at 360px with
/// text x2.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/owner_switches_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart' show buildAuthHarness, okMe;

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

// NK292_17
final class _Server {
  String mode = 'normal';
  String? reason;
  final List<http.Request> puts = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (path == '/owner/mode') {
      if (request.method == 'PUT') {
        puts.add(request);
        final Map<Object?, Object?> body =
            jsonDecode(request.body) as Map<Object?, Object?>;
        mode = body['mode']! as String;
        reason = body['reason']! as String;
      }
      return _json({
        'schema_version': 1,
        'mode': mode,
        'reason': reason,
        'changed_by': reason == null ? null : 'you',
        'changed_at': '2026-11-20T12:00:00.000Z',
      });
    }
    if (path == '/owner/switches') {
      return _json({'schema_version': 1, 'switches': <Object?>[]});
    }
    return okMe(
      const AuthenticatedUserDto(
        userId: 'u-owner-id',
        role: 'admin',
        status: 'active',
        isOwner: true,
      ),
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  double textScale = 1.0,
}) async {
  const Size size = Size(1080, 2340);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        home: MediaQuery(
          data: MediaQueryData(
            size: size / 3,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(body: OwnerSwitchesSection()),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('read only, set with a reason', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    expect(find.text('وضع التطبيق'), findsOneWidget);
    final ChoiceChip normal = tester.widget(
      find.byKey(const Key('admin.mode.normal')),
    );
    expect(normal.selected, isTrue);

    await tester.tap(find.byKey(const Key('admin.mode.read_only')));
    await tester.pumpAndSettle();
    expect(find.text('وضع التطبيق: قراءة فقط'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('admin.switches.dialog.reason')),
      'خطأ في النقاط',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.switches.dialog.ok')));
    await tester.pumpAndSettle();

    expect(jsonDecode(server.puts.single.body), {
      'mode': 'read_only',
      'reason': 'خطأ في النقاط',
    });
    final ChoiceChip readOnly = tester.widget(
      find.byKey(const Key('admin.mode.read_only')),
    );
    expect(readOnly.selected, isTrue);
    final Text changed = tester.widget(
      find.byKey(const Key('admin.mode.changed')),
    );
    expect(changed.data, contains('السبب: خطأ في النقاط'));
  });

  testWidgets('a cancelled dialog changes nothing', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    await tester.tap(find.byKey(const Key('admin.mode.closed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.switches.dialog.cancel')));
    await tester.pumpAndSettle();

    expect(server.puts, isEmpty);
  });

  testWidgets('fits a 360px phone at text x2', (tester) async {
    final _Server server = _Server()
      ..mode = 'closed'
      ..reason = 'صيانة طارئة بعد خطأ في احتساب النقاط';
    await _open(tester, server, textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('وضع التطبيق'), findsOneWidget);
  });
}
