/// The owners' switches (script 289) through the real providers and the
/// real `AdminApi`, over the auth harness's fake server: «الإدارة العامة
/// للمالك» opens on «المفاتيح»; the crowning switch shows its state and its
/// last change, and turns only once a reason is typed. Also drawn at 360px
/// with text x2.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/ui/app_button.dart';
import 'package:mobile/features/admin/admin_shell.dart';
import 'package:mobile/features/admin/screens/sections/owner_switches_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const AuthenticatedUserDto _owner = AuthenticatedUserDto(
  userId: 'u-owner-id',
  role: 'admin',
  status: 'active',
  email: 'owner@example.com',
  isOwner: true,
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

// NK289_16
final class _Server {
  _Server({this.reason, this.by});

  bool on = true;
  String? reason;
  String? by;
  String at = '2026-11-20T00:00:00.000Z';
  final List<http.Request> requests = <http.Request>[];

  Map<String, Object?> _line() => {
    'key': 'crowning',
    'is_on': on,
    'reason': reason,
    'changed_by': by,
    'changed_at': at,
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/owner/switches') {
      return _json({
        'schema_version': 1,
        'switches': [_line()],
      });
    }
    if (path == '/owner/switches/crowning' && request.method == 'PUT') {
      final Map<String, Object?> body =
          (jsonDecode(request.body) as Map<Object?, Object?>)
              .cast<String, Object?>();
      on = body['is_on']! as bool;
      reason = body['reason']! as String;
      by = 'you';
      at = '2026-11-30T18:00:00.000Z';
      return _json(_line());
    }
    return okMe(_owner);
  }

  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _open(
  WidgetTester tester,
  _Server server,
  Widget body, {
  double textScale = 1.0,
}) async {
  const Size size = Size(1080, 2340);
  const double ratio = 3.0;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        home: MediaQuery(
          data: MediaQueryData(
            size: size / ratio,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: body),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the owner page opens on the switches', (tester) async {
    await _open(tester, _Server(), const OwnerGeneralSection());

    expect(find.text('المفاتيح'), findsOneWidget);
    expect(find.text('الشعارات'), findsOneWidget);
    expect(find.text('تتويج الشهر'), findsOneWidget);
  });

  testWidgets('shows the crowning on, never changed', (tester) async {
    await _open(tester, _Server(), const OwnerSwitchesSection());

    final SwitchListTile tile = tester.widget(
      find.byKey(const Key('admin.switches.crowning')),
    );
    expect(tile.value, isTrue);
    expect(find.text('لم يتغير منذ إنشائه'), findsOneWidget);
  });

  testWidgets('turns the crowning off only with a reason', (tester) async {
    final server = _Server();
    await _open(tester, server, const OwnerSwitchesSection());

    await _tap(tester, const Key('admin.switches.crowning'));
    expect(find.text('إيقاف «تتويج الشهر»'), findsOneWidget);
    final AppButton ok = tester.widget(
      find.byKey(const Key('admin.switches.dialog.ok')),
    );
    expect(ok.onPressed, isNull, reason: 'no reason typed yet');

    await tester.enterText(
      find.byKey(const Key('admin.switches.dialog.reason')),
      'مراجعة نقاط الشهر',
    );
    await tester.pumpAndSettle();
    await _tap(tester, const Key('admin.switches.dialog.ok'));

    final sent = server.to('/owner/switches/crowning').single;
    expect(sent.method, 'PUT');
    expect(jsonDecode(sent.body), {
      'is_on': false,
      'reason': 'مراجعة نقاط الشهر',
    });
    expect(find.text('أُوقف «تتويج الشهر»'), findsOneWidget);
    final SwitchListTile tile = tester.widget(
      find.byKey(const Key('admin.switches.crowning')),
    );
    expect(tile.value, isFalse);
    final Text changed = tester.widget(
      find.byKey(const Key('admin.switches.crowning.changed')),
    );
    expect(changed.data, contains('بواسطتك'));
    expect(changed.data, contains('السبب: مراجعة نقاط الشهر'));
  });

  testWidgets('a cancelled dialog changes nothing', (tester) async {
    final server = _Server();
    await _open(tester, server, const OwnerSwitchesSection());

    await _tap(tester, const Key('admin.switches.crowning'));
    await _tap(tester, const Key('admin.switches.dialog.cancel'));

    expect(server.to('/owner/switches/crowning'), isEmpty);
    final SwitchListTile tile = tester.widget(
      find.byKey(const Key('admin.switches.crowning')),
    );
    expect(tile.value, isTrue);
  });

  testWidgets('a change from the SQL editor says so', (tester) async {
    final server = _Server(reason: 'إيقاف احترازي', by: 'sql')..on = false;
    await _open(tester, server, const OwnerSwitchesSection());

    final Text changed = tester.widget(
      find.byKey(const Key('admin.switches.crowning.changed')),
    );
    expect(changed.data, contains('من محرر SQL'));
    expect(
      find.byKey(const Key('admin.switches.crowning.state')),
      findsOneWidget,
    );
  });

  testWidgets('fits a 360px phone at text x2', (tester) async {
    final server = _Server(reason: 'مراجعة نقاط الشهر قبل التتويج', by: 'other')
      ..on = false;
    await _open(tester, server, const OwnerSwitchesSection(), textScale: 2.0);

    expect(tester.takeException(), isNull);
    // script 292: the card of the app's mode sits above the switches now.
    await tester.scrollUntilVisible(
      find.text('تتويج الشهر'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('admin.switches.list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('تتويج الشهر'), findsOneWidget);
  });
}
