/// Account switching through the real [SessionScope] and [SessionGate]:
/// signing out throws away everything the previous account had cached.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/session/session_scope.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/session_controller.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

int _probeBuilds = 0;

/// Kept alive like the app's cached reads; counts how often it is built.
final Provider<int> _probe = Provider<int>((ref) => ++_probeBuilds);

void main() {
  testWidgets('signing out starts the next account with nothing cached', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _probeBuilds = 0;
    final harness = buildAuthHarness(
      (_) async => okMe(sampleUser),
      seedToken: 'saved-jwt',
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      SessionScope(
        overrides: harness.overrides,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Column(
            children: <Widget>[
              Consumer(
                builder: (_, ref, _) => Text('probe ${ref.watch(_probe)}'),
              ),
              const Expanded(child: SessionGate()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('probe 1'), findsOneWidget);
    expect(find.byType(NukhbaaShell), findsOneWidget);

    await ProviderScope.containerOf(
      tester.element(find.byType(SessionGate)),
    ).read(sessionControllerProvider.notifier).signOut();
    await tester.pumpAndSettle();

    expect(find.text('probe 2'), findsOneWidget, reason: 'a fresh container');
    expect(find.byKey(const Key('signIn.title')), findsOneWidget);
    expect(find.byType(NukhbaaShell), findsNothing);
  });
}
