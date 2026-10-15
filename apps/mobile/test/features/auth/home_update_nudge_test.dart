/// The home reminder of a waiting update (batch 147): shown when the update
/// check raised it, it installs the waiting release in-app, and the cross
/// closes it for this run of the app.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/features/update/in_app_updater.dart';
import 'package:mobile/features/update/update_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart' show sampleUser;
import '../../support/current_month_fixtures_harness.dart';

const LatestBuildDto _release = LatestBuildDto(
  publishedAt: '2026-10-15T03:00:00Z',
  apkUrl:
      'https://github.com/adbrhman/nukhbaa/releases/download/'
      'build-bbbbbbb/nukhbaa-arm64-v8a-bbbbbbb.apk',
);

class _Raised extends UpdateNudge {
  @override
  bool build() => true;
}

class _Waiting extends PendingUpdate {
  @override
  LatestBuildDto? build() => _release;
}

final class _FakeUpdater implements InAppUpdater {
  final List<LatestBuildDto> started = <LatestBuildDto>[];

  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) {
    started.add(build);
    return Stream<UpdateProgress>.value(
      const UpdateProgress(UpdatePhase.completed),
    );
  }

  @override
  Future<void> cancel() async {}
}

Future<_FakeUpdater> _pump(WidgetTester tester, {required bool raised}) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildCurrentMonthFixturesHarness((request) async {
    final path = request.url.path;
    if (path == '/feed/current-month-fixtures' ||
        path == '/me/fixture-predictions' ||
        path == '/teams') {
      return okJsonList(const []);
    }
    return http.Response('not found', 404);
  });
  addTearDown(harness.dispose);
  final _FakeUpdater updater = _FakeUpdater();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        inAppUpdaterProvider.overrideWithValue(updater),
        pendingUpdateProvider.overrideWith(_Waiting.new),
        if (raised) updateNudgeProvider.overrideWith(_Raised.new),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: HomeScreen(
          user: sampleUser,
          onOpenMatches: () {},
          onOpenAccount: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return updater;
}

void main() {
  testWidgets('nothing until the update check raises it', (tester) async {
    await _pump(tester, raised: false);

    expect(find.byKey(const Key('home.updateNudge')), findsNothing);
  });

  testWidgets('it installs the waiting release in-app', (tester) async {
    final _FakeUpdater updater = await _pump(tester, raised: true);

    expect(find.byKey(const Key('home.updateNudge')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home.updateNudge.update')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(updater.started.single, _release);
  });

  testWidgets('the cross closes it', (tester) async {
    await _pump(tester, raised: true);

    await tester.tap(find.byKey(const Key('home.updateNudge.close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home.updateNudge')), findsNothing);
  });
}
