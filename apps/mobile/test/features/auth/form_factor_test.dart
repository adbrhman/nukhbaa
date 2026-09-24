/// Form factors the visual probe (46_visual_probe) rendered, through the real
/// widgets: on a tablet the shell keeps its tabs at a phone-like reading
/// width instead of stretching cards and tables edge to edge; the home
/// button draws in the app's own typeface (it had fallen back to the
/// system font); and a list still loading in a short landscape viewport
/// no longer overflows its placeholder column.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/design/app_sizes.dart';
import 'package:mobile/core/design/app_typography.dart';
import 'package:mobile/core/session/session_scope.dart';
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';
import '../../support/prediction_harness.dart' as ph;

void _view(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpShell(WidgetTester tester) async {
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
        locale: const Locale('ar'),
        home: const SessionGate(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tablet: the home tab keeps the content width, centred', (
    tester,
  ) async {
    _view(tester, const Size(1280, 800));
    await _pumpShell(tester);

    final Finder home = find.byType(HomeScreen);
    expect(home, findsOneWidget);
    expect(tester.getSize(home).width, AppSizes.maxContentWidth);
    expect(tester.getCenter(home).dx, 640);
  });

  testWidgets('phone: the home tab still spans the screen', (tester) async {
    _view(tester, const Size(360, 780));
    await _pumpShell(tester);

    expect(tester.getSize(find.byType(HomeScreen)).width, 360);
  });

  testWidgets('the home call to action draws in the app typeface', (
    tester,
  ) async {
    _view(tester, const Size(360, 780));
    await _pumpShell(tester);

    final RenderParagraph label = tester.renderObject<RenderParagraph>(
      find.text('ابدأ التوقع'),
    );
    expect(label.text.style?.fontFamily, AppTypography.fontFamily);
  });

  testWidgets('landscape: a loading list does not overflow', (tester) async {
    _view(tester, const Size(780, 360));
    final harness = ph.buildPredictionHarness(
      (_) => Completer<http.Response>().future,
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          locale: const Locale('ar'),
          home: const PredictionHistoryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('browse.loading')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
