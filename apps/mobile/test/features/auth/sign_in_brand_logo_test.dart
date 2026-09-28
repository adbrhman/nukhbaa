/// The signed-out gate shows the brand logo in the sign-in header, loaded
/// from the asset the app bundle actually declares in pubspec.yaml.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/auth/google_id_token_source.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/auth/sign_in_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../support/auth_harness.dart';

final class _NoGoogle implements GoogleIdTokenSource {
  @override
  bool get isSupported => false;

  @override
  Future<Result<String?>> pickIdToken() async => const Result.ok(null);
}

Future<http.Response> _server(http.Request request) async => okMe(sampleUser);

void main() {
  testWidgets('the sign-in header shows the bundled brand logo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = buildAuthHarness(_server, googleIdTokenSource: _NoGoogle());
    addTearDown(harness.dispose);

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

    expect(find.byType(SignInScreen), findsOneWidget);
    final Finder logo = find.byKey(const Key('signIn.brandLogo'));
    expect(logo, findsOneWidget);
    final Image image = tester.widget<Image>(
      find.descendant(of: logo, matching: find.byType(Image)),
    );
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, kBrandLogoAsset);

    final data = await tester.runAsync(() => rootBundle.load(kBrandLogoAsset));
    expect(data, isNotNull);
    expect(data!.lengthInBytes, greaterThan(0));
  });
}
