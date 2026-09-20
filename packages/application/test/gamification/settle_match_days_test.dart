import 'package:application/application.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('SettleMatchDays', () {
    // 2026-09-20 10:00 in Riyadh (UTC+3) is 07:00 UTC.
    final morning = DateTime.utc(2026, 9, 20, 7);

    late _FakeStore store;
    late SettleMatchDays useCase;

    setUp(() {
      store = _FakeStore();
      useCase = SettleMatchDays(store: store);
    });

    test(
      'the first run starts at the earliest fixture, ends yesterday',
      () async {
        store.first = DateTime.utc(2026, 9, 10);

        final result = await useCase(now: morning);

        expect((result as Ok<int>).value, 10);
        expect(store.calls, hasLength(1));
        expect(store.calls.single.from, DateTime.utc(2026, 9, 10));
        expect(store.calls.single.through, DateTime.utc(2026, 9, 19));
      },
    );

    test('continues from the day after the newest settled day', () async {
      store.last = DateTime.utc(2026, 9, 15);

      final result = await useCase(now: morning);

      expect((result as Ok<int>).value, 4);
      expect(store.calls.single.from, DateTime.utc(2026, 9, 16));
      expect(store.calls.single.through, DateTime.utc(2026, 9, 19));
      expect(store.firstReads, 0);
    });

    test('does nothing once yesterday is settled', () async {
      store.last = DateTime.utc(2026, 9, 19);

      final result = await useCase(now: morning);

      expect((result as Ok<int>).value, 0);
      expect(store.calls, isEmpty);
    });

    test('a second run right after the first changes nothing', () async {
      store.first = DateTime.utc(2026, 9, 10);

      await useCase(now: morning);
      final again = await useCase(now: morning);

      expect((again as Ok<int>).value, 0);
      expect(store.calls, hasLength(1));
    });

    test('yesterday waits for the grace period after midnight', () async {
      store.last = DateTime.utc(2026, 9, 17);

      // 00:30 Riyadh on 20 Sep: the 19th ended half an hour ago.
      await useCase(now: DateTime.utc(2026, 9, 19, 21, 30));
      expect(store.calls.single.from, DateTime.utc(2026, 9, 18));
      expect(store.calls.single.through, DateTime.utc(2026, 9, 18));

      // 03:00 Riyadh on 20 Sep: the grace is over, the 19th is settled.
      await useCase(now: DateTime.utc(2026, 9, 20));
      expect(store.calls.last.from, DateTime.utc(2026, 9, 19));
      expect(store.calls.last.through, DateTime.utc(2026, 9, 19));
    });

    test('with no fixture at all there is nothing to settle', () async {
      final result = await useCase(now: morning);

      expect((result as Ok<int>).value, 0);
      expect(store.calls, isEmpty);
    });

    test('a first run in the future settles nothing', () async {
      store.first = DateTime.utc(2026, 10);

      final result = await useCase(now: morning);

      expect((result as Ok<int>).value, 0);
      expect(store.calls, isEmpty);
    });

    test('a long outage is made good a capped span at a time', () async {
      useCase = SettleMatchDays(store: store, maxDaysPerRun: 5);
      store.first = DateTime.utc(2026, 9);

      await useCase(now: morning);
      expect(store.calls.last.from, DateTime.utc(2026, 9));
      expect(store.calls.last.through, DateTime.utc(2026, 9, 5));

      await useCase(now: morning);
      expect(store.calls.last.from, DateTime.utc(2026, 9, 6));
      expect(store.calls.last.through, DateTime.utc(2026, 9, 10));
    });

    test(
      'a store failure comes back as an error and settles nothing',
      () async {
        store.failLast = const AppError.transient('db.query_failed', 'down');
        final onLast = await useCase(now: morning);
        expect(onLast, isA<Err<int>>());

        store.failLast = null;
        store.failFirst = const AppError.transient('db.query_failed', 'down');
        final onFirst = await useCase(now: morning);
        expect(onFirst, isA<Err<int>>());

        store
          ..failFirst = null
          ..first = DateTime.utc(2026, 9, 10)
          ..failSettle = const AppError.transient('db.query_failed', 'down');
        final onSettle = await useCase(now: morning);
        expect((onSettle as Err<int>).error.code, 'db.query_failed');
      },
    );
  });
}

/// One `settle` call the use-case made.
final class _Call {
  const _Call(this.from, this.through);

  final DateTime from;
  final DateTime through;
}

/// An in-memory [MatchDaySettlementStore]: settling moves the watermark, as
/// the real store's inserted rows do.
final class _FakeStore implements MatchDaySettlementStore {
  DateTime? last;
  DateTime? first;
  AppError? failLast;
  AppError? failFirst;
  AppError? failSettle;
  int firstReads = 0;
  final List<_Call> calls = <_Call>[];

  @override
  Future<Result<DateTime?>> lastSettledDay() async {
    final error = failLast;
    if (error != null) {
      return Result.err(error);
    }
    return Result.ok(last);
  }

  @override
  Future<Result<DateTime?>> firstFixtureDay() async {
    firstReads++;
    final error = failFirst;
    if (error != null) {
      return Result.err(error);
    }
    return Result.ok(first);
  }

  @override
  Future<Result<int>> settle({
    required DateTime from,
    required DateTime through,
  }) async {
    final error = failSettle;
    if (error != null) {
      return Result.err(error);
    }
    calls.add(_Call(from, through));
    last = through;
    return Result.ok(through.difference(from).inDays + 1);
  }
}
