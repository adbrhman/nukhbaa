import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/platform/cached_app_update_policy_store.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The row behind the cache, counting reads; fails while [failing].
final class _Row implements AppUpdatePolicyStore {
  int? value;
  int reads = 0;
  bool failing = false;

  @override
  Future<Result<int?>> minSupportedBuild() async {
    reads++;
    await Future<void>.delayed(Duration.zero);
    return failing
        ? const Result.err(AppError.transient('db.down', 'down'))
        : Result.ok(value);
  }

  @override
  Future<Result<int?>> setMinSupportedBuild({
    required int? buildNumber,
    required UserId by,
  }) async {
    if (failing) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    value = buildNumber;
    return Result.ok(value);
  }
}

const UserId _admin = UserId('00000000-0000-4000-8000-0000000000ad');

void main() {
  test('one read a minute, shared by concurrent callers', () async {
    var now = DateTime.utc(2026, 10, 26, 12);
    final row = _Row()..value = 800;
    final store = CachedAppUpdatePolicyStore(row, now: () => now);

    final results = await Future.wait([
      store.minSupportedBuild(),
      store.minSupportedBuild(),
      store.minSupportedBuild(),
    ]);
    expect(results.map((r) => (r as Ok<int?>).value), [800, 800, 800]);
    expect(row.reads, 1);

    now = now.add(const Duration(seconds: 59));
    await store.minSupportedBuild();
    expect(row.reads, 1);

    row.value = 810;
    now = now.add(const Duration(seconds: 2));
    expect(((await store.minSupportedBuild()) as Ok<int?>).value, 810);
    expect(row.reads, 2);
  });

  test("an admin's change is held at once; a failed one drops what is "
      'held', () async {
    final row = _Row()..value = 800;
    final store = CachedAppUpdatePolicyStore(row);
    await store.minSupportedBuild();

    await store.setMinSupportedBuild(buildNumber: null, by: _admin);
    expect(((await store.minSupportedBuild()) as Ok<int?>).value, isNull);
    expect(row.reads, 1);

    row.failing = true;
    final failed = await store.setMinSupportedBuild(
      buildNumber: 820,
      by: _admin,
    );
    expect(failed, isA<Err<int?>>());
    expect(await store.minSupportedBuild(), isA<Err<int?>>());
    expect(row.reads, 2);
  });

  test('a failed read is not held', () async {
    final row = _Row()..failing = true;
    final store = CachedAppUpdatePolicyStore(row);

    expect(await store.minSupportedBuild(), isA<Err<int?>>());
    row.failing = false;
    row.value = 800;
    expect(((await store.minSupportedBuild()) as Ok<int?>).value, 800);
    expect(row.reads, 2);
  });
}
