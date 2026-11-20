/// Script 291: the predictions and chat switches on the owners' page,
/// through the real providers and `AdminApi` over the auth harness's fake
/// server: each reads its own state, and turns with a reason.
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

// NK291_08
void main() {
  testWidgets('predictions off and chat on, and chat turned off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final Map<String, bool> on = {
      'crowning': true,
      'predictions': false,
      'chat': true,
    };
    final List<http.Request> puts = <http.Request>[];
    Map<String, Object?> line(String key) => {
      'key': key,
      'is_on': on[key],
      'reason': null,
      'changed_by': null,
      'changed_at': '2026-11-20T00:00:00.000Z',
    };
    final harness = buildAuthHarness((request) async {
      final String path = request.url.path;
      if (path == '/owner/switches') {
        return http.Response(
          jsonEncode({
            'schema_version': 1,
            'switches': [for (final k in on.keys) line(k)],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/owner/switches/chat') {
        puts.add(request);
        on['chat'] = false;
        return http.Response(
          jsonEncode(line('chat')),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return okMe(
        const AuthenticatedUserDto(
          userId: 'u-owner-id',
          role: 'admin',
          status: 'active',
          isOwner: true,
        ),
      );
    }, seedToken: 'admin-jwt');
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          locale: const Locale('ar'),
          home: const Scaffold(body: OwnerSwitchesSection()),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('حفظ التوقعات'), findsOneWidget);
    final Text predictions = tester.widget(
      find.byKey(const Key('admin.switches.predictions.state')),
    );
    expect(predictions.data, startsWith('موقوف'));

    await tester.ensureVisible(find.byKey(const Key('admin.switches.chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.switches.chat')));
    await tester.pumpAndSettle();
    expect(find.text('إيقاف «دردشة المواجهات»'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('admin.switches.dialog.reason')),
      'رسائل مسيئة',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.switches.dialog.ok')));
    await tester.pumpAndSettle();

    expect(jsonDecode(puts.single.body), {
      'is_on': false,
      'reason': 'رسائل مسيئة',
    });
    final SwitchListTile chat = tester.widget(
      find.byKey(const Key('admin.switches.chat')),
    );
    expect(chat.value, isFalse);
  });
}
