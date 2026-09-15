import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _f1 = 'ffffffff-0000-0000-0000-000000000001';
const _f2 = 'ffffffff-0000-0000-0000-000000000002';

final class _CountingTotals implements FixtureTotalsReader {
  int calls = 0;
  Result<List<ParticipantFixtureTotals>> next = const Result.ok(
    <ParticipantFixtureTotals>[],
  );

  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async {
    calls++;
    return next;
  }
}

void main() {
  late DateTime clock;
  late _CountingTotals inner;
  late CachedFixtureTotalsReader reader;

  setUp(() {
    clock = DateTime.utc(2026, 9, 16, 12);
    inner = _CountingTotals();
    reader = CachedFixtureTotalsReader(inner, now: () => clock);
  });

  test('a repeat read inside the ttl is served from the cache', () async {
    await reader.totalsFor(const [FixtureRef(_f1), FixtureRef(_f2)]);
    await reader.totalsFor(const [FixtureRef(_f2), FixtureRef(_f1)]);
    expect(inner.calls, 1);
  });

  test('the cache expires after the ttl', () async {
    await reader.totalsFor(const [FixtureRef(_f1)]);
    clock = clock.add(const Duration(seconds: 30));
    await reader.totalsFor(const [FixtureRef(_f1)]);
    expect(inner.calls, 2);
  });

  test('different fixture sets are cached separately', () async {
    await reader.totalsFor(const [FixtureRef(_f1)]);
    await reader.totalsFor(const [FixtureRef(_f2)]);
    expect(inner.calls, 2);
  });

  test('failures are not cached', () async {
    inner.next = const Result.err(AppError.transient('db.down', 'down'));
    await reader.totalsFor(const [FixtureRef(_f1)]);
    inner.next = const Result.ok(<ParticipantFixtureTotals>[]);
    final second = await reader.totalsFor(const [FixtureRef(_f1)]);
    expect(inner.calls, 2);
    expect(second, isA<Ok<List<ParticipantFixtureTotals>>>());
  });
}
