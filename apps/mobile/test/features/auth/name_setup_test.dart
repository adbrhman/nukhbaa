/// The one-time name choice through the real [SessionGate]: an account that
/// still carries the automatic name must choose one before the app opens;
/// an account with a chosen name goes straight in.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

AuthenticatedUserDto _me(String displayName) => AuthenticatedUserDto(
  userId: 'u-1',
  role: 'user',
  status: 'active',
  email: 'n72914939@gmail.com',
  displayName: displayName,
);

void _gateTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await body(tester);
  });
}

/// A server holding one account named [name]; `PUT /me/display-name`
/// renames it and records each body.
final class _Server {
  _Server(this.name);

  String name;
  final List<String> puts = <String>[];

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/me/display-name' && request.method == 'PUT') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      name = body['display_name']! as String;
      puts.add(name);
    }
    return okMe(_me(name));
  }
}

Future<void> _open(WidgetTester tester, AuthHarness harness) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const SessionGate(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  _gateTest('an automatic name must be replaced before the app opens', (
    tester,
  ) async {
    final server = _Server('n72914939');
    final harness = buildAuthHarness(server.handle, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);

    await _open(tester, harness);

    expect(find.byKey(const Key('nameSetup.screen')), findsOneWidget);
    expect(find.byType(NukhbaaShell), findsNothing);

    await tester.enterText(find.byKey(const Key('nameSetup.field')), 'Ali');
    await tester.tap(find.byKey(const Key('nameSetup.save')));
    await tester.pumpAndSettle();

    expect(server.puts, ['Ali']);
    expect(find.byKey(const Key('nameSetup.screen')), findsNothing);
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });

  _gateTest('the automatic name itself is refused without a request', (
    tester,
  ) async {
    final server = _Server('n72914939');
    final harness = buildAuthHarness(server.handle, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);

    await _open(tester, harness);
    await tester.enterText(
      find.byKey(const Key('nameSetup.field')),
      'n72914939',
    );
    await tester.tap(find.byKey(const Key('nameSetup.save')));
    await tester.pumpAndSettle();

    expect(server.puts, isEmpty);
    expect(find.byKey(const Key('nameSetup.screen')), findsOneWidget);
  });

  _gateTest('a chosen name goes straight into the app', (tester) async {
    final server = _Server('Abdulrahman');
    final harness = buildAuthHarness(server.handle, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);

    await _open(tester, harness);

    expect(find.byKey(const Key('nameSetup.screen')), findsNothing);
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });
}
