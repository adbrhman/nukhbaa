import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/update/in_app_updater.dart';

/// Scriptable fake exercising phase/fallback semantics without native calls.
class FakeUpdater implements InAppUpdater {
  FakeUpdater(this._events, {this.returnsNull = false});
  final List<UpdateProgress> _events;
  final bool returnsNull;
  bool cancelled = false;

  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) =>
      returnsNull ? null : Stream<UpdateProgress>.fromIterable(_events);

  @override
  Future<void> cancel() async => cancelled = true;
}

LatestBuildDto _dto() => const LatestBuildDto(
  publishedAt: '2026-01-01T00:00:00Z',
  apkUrl: 'https://example.com/a.apk',
  sha256: 'x',
  assets: [
    BuildAssetDto(
      abi: 'arm64-v8a',
      url: 'https://example.com/arm64.apk',
      sha256: 'y',
    ),
  ],
);

void main() {
  test('completed is terminal & NOT a failure (no fallback)', () async {
    final fake = FakeUpdater(const [
      UpdateProgress(UpdatePhase.downloading, percent: 50),
      UpdateProgress(UpdatePhase.installing),
      UpdateProgress(UpdatePhase.completed),
    ]);
    final events = await fake.start(_dto())!.toList();
    expect(events.last.phase, UpdatePhase.completed);
    expect(events.last.isTerminal, isTrue);
    expect(events.last.isFailure, isFalse);
  });

  test('cancelled is terminal & NOT a failure (no fallback)', () {
    const p = UpdateProgress(UpdatePhase.cancelled);
    expect(p.isTerminal, isTrue);
    expect(p.isFailure, isFalse);
  });

  test('checksum failure IS a failure (=> fallback)', () {
    const p = UpdateProgress(UpdatePhase.checksumFailed);
    expect(p.isFailure, isTrue);
  });

  test('download failure IS a failure (=> fallback)', () {
    expect(const UpdateProgress(UpdatePhase.downloadFailed).isFailure, isTrue);
  });

  test('install failure IS a failure (=> fallback)', () {
    expect(const UpdateProgress(UpdatePhase.installFailed).isFailure, isTrue);
  });

  test('null stream signals caller to use browser fallback', () {
    final fake = FakeUpdater(const [], returnsNull: true);
    expect(fake.start(_dto()), isNull);
  });
}
