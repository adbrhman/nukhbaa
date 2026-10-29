/// The match card's share button through the real matches screen, the real
/// card and a fake server (script 136): the text it hands the share sheet
/// says the player called the score ("توقعت"), never that they hit it
/// ("أصبت") -- the card offers the share before kickoff, when nothing has
/// been hit yet. The hit wording stays for the exact-hit card in My
/// Predictions, which only opens once the scoreline was right.
library;

import 'dart:io' as io;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/competition/team_registry.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

/// The channel share_plus sends the text through in a test run.
const MethodChannel _shareChannel = MethodChannel(
  'dev.fluttercommunity.plus/share',
);
const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

Map<String, Object?> _item() => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'League',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    kickoffAt: futureIso(),
  ),
  homeOutcomeShare: 60,
  drawOutcomeShare: 22,
  awayOutcomeShare: 18,
  totalPredictions: 100,
).toJson();

Map<String, Object?> _call() => FixturePredictionDto(
  id: 'pr-f-1',
  participantId: 'p-me',
  fixtureId: 'f-1',
  submittedAt: '2026-10-18T10:00:00.000Z',
  homeGoals: 2,
  awayGoals: 1,
  isDouble: false,
  seasonId: 's-1',
).toJson();

void main() {
  testWidgets('an upcoming call is shared as a call, not as a hit', (
    tester,
  ) async {
    final List<MethodCall> sent = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _shareChannel,
      (MethodCall call) async {
        sent.add(call);
        return 'dev.fluttercommunity.plus/share/unavailable';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _shareChannel,
        null,
      ),
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _pathProviderChannel,
      (MethodCall call) async {
        if (call.method == 'getTemporaryDirectory') {
          return io.Directory.systemTemp.path;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _pathProviderChannel,
        null,
      ),
    );

    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final harness = buildCurrentMonthFixturesHarness((request) async {
      switch (request.url.path) {
        case '/feed/current-month-fixtures':
          return okJsonList(<Map<String, Object?>>[_item()]);
        case '/me/fixture-predictions':
          return okJsonList(<Map<String, Object?>>[_call()]);
        case '/teams':
          return okJsonList(const []);
      }
      return http.Response('not found', 404);
    });
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          locale: const Locale('ar'),
          home: const CurrentMonthFixturesScreen(),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final Finder share = find.byKey(
      const Key('currentMonthFixtures.sharePrediction.f-1'),
    );
    expect(share, findsOneWidget);
    await tester.ensureVisible(share);
    await tester.pump();
    await tester.tap(share);
    for (var i = 0; i < 20 && sent.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(
      sent,
      hasLength(1),
      reason: 'one tap hands an image and caption to the sheet',
    );
    final Map<Object?, Object?> args =
        sent.single.arguments as Map<Object?, Object?>;
    final String text = args['text']! as String;
    final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));
    final String call = ar.matchCardShareMessage(
      teamDisplayName('Arsenal'),
      '2-1',
      teamDisplayName('Chelsea'),
    );
    expect(text, '$call\n${ar.shareHitJoin('https://nukhbaa.app')}');
    expect(text, startsWith('توقعت '));
    expect(text, isNot(contains('أصبت')));
    final List<dynamic> imagePaths = args['paths']! as List<dynamic>;
    expect(imagePaths, hasLength(1));
    expect(imagePaths.single, endsWith('nukhba-prediction.png'));
    expect(args['mimeTypes'], <String>['image/png']);
    final io.File sharedImage = io.File(imagePaths.single as String);
    expect(sharedImage.existsSync(), isTrue);
    expect(sharedImage.readAsBytesSync().take(8).toList(), <int>[
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ]);
  });
}
