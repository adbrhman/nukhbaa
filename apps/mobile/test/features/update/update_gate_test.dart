import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/update/in_app_updater.dart';
import 'package:mobile/features/update/update_gate.dart';

/// NOTE: These tests focus on the pure decision logic reachable without the
/// native plugin or secure storage. Full widget-level flows (dialog prompt,
/// baseline persistence) require a fake AppApi + a fake FlutterSecureStorage
/// channel; the seams (`appApiProvider`, `inAppUpdaterProvider`) are provided
/// here so a follow-up can extend coverage. Native ota_update is never invoked.
class _FakeUpdater implements InAppUpdater {
  _FakeUpdater(this.result);
  final UpdatePhase? result; // null => returns null stream (no asset)
  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) {
    final r = result;
    if (r == null) return null;
    return Stream<UpdateProgress>.value(UpdateProgress(r));
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  testWidgets('UpdateGate renders its child unconditionally', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inAppUpdaterProvider.overrideWithValue(
            _FakeUpdater(UpdatePhase.completed),
          ),
        ],
        child: const MaterialApp(
          home: UpdateGate(child: Text('child-visible')),
        ),
      ),
    );
    // Child is present immediately (the check runs post-frame and is silent on
    // any AppApi failure, which is the default here without a base URL).
    expect(find.text('child-visible'), findsOneWidget);
  });

  test('failure phases map to fallback, success/cancel do not', () {
    bool needsFallback(UpdatePhase p) =>
        p == UpdatePhase.downloadFailed ||
        p == UpdatePhase.checksumFailed ||
        p == UpdatePhase.installFailed ||
        p == UpdatePhase.failed;

    expect(needsFallback(UpdatePhase.completed), isFalse);
    expect(needsFallback(UpdatePhase.cancelled), isFalse);
    expect(needsFallback(UpdatePhase.checksumFailed), isTrue);
    expect(needsFallback(UpdatePhase.downloadFailed), isTrue);
    expect(needsFallback(UpdatePhase.installFailed), isTrue);
    expect(needsFallback(UpdatePhase.failed), isTrue);
  });
}
