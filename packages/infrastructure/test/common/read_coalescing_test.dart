import 'dart:async';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The burst of 2026-10-11 (20:41 UTC): when a match ended, 150 to 180
/// requests for the same fixture reached the pool at once. Each read cache
/// now lets the requests that arrive while an answer is loading share that
/// load, so the database sees one query, not one per request.

const _f1 = 'ffffffff-0000-0000-0000-000000000001';
const _f2 = 'ffffffff-0000-0000-0000-000000000002';
const _s1 = 'cccccccc-0000-0000-0000-000000000001';

const _down = Result<Never>.err(AppError.transient('db.down', 'down'));

/// Holds every read until [open] is called, counting how many reached it.
final class _Gate {
  int reads = 0;
  final Completer<void> _release = Completer<void>();

  Future<void> pass() async {
    reads++;
    await _release.future;
  }

  void open() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }
}

final class _GatedScores implements FixtureScoreRepository {
  final _Gate gate = _Gate();
  int batchReads = 0;

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async {
    await gate.pass();
    return const Result.ok(<ParticipantFixtureScore>[]);
  }

  @override
  Future<Result<List<ParticipantFixtureScore>>> listBySeasonFixtures(
    List<FixtureRef> fixtures,
  ) async {
    batchReads++;
    await gate.pass();
    return const Result.ok(<ParticipantFixtureScore>[]);
  }

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async => const Result.ok(null);
}

final class _GatedResults implements FixtureResultRepository {
  final _Gate gate = _Gate();
  Result<FixtureResult?> next = const Result.ok(null);
  int upserts = 0;

  @override
  Future<Result<FixtureResult?>> findByFixture(FixtureRef fixture) async {
    await gate.pass();
    return next;
  }

  @override
  Future<Result<List<FixtureResult>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    await gate.pass();
    return const Result.ok(<FixtureResult>[]);
  }

  @override
  Future<Result<void>> upsert(FixtureResult result, DateTime recordedAt) async {
    upserts++;
    return const Result.ok(null);
  }
}

final class _GatedPredictions implements FixturePredictionRepository {
  final _Gate linkGate = _Gate();
  final _Gate listGate = _Gate();
  final _Gate seasonGate = _Gate();
  Result<SeasonFixture?> nextLink = const Result.ok(null);
  int unlinks = 0;
  int userReads = 0;

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    await linkGate.pass();
    return nextLink;
  }

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async {
    await listGate.pass();
    return const Result.ok(<FixturePredictionView>[]);
  }

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async {
    unlinks++;
    return const Result.ok(true);
  }

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async {
    userReads++;
    return const Result.ok(<FixturePredictionView>[]);
  }

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async =>
      const Result.ok(null);

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async => const Result.ok(0);

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) async {
    await seasonGate.pass();
    return const Result.ok(<FixtureRef>[FixtureRef(_f1), FixtureRef(_f2)]);
  }
}

/// Starts [count] reads at once, lets them reach the gate, then opens it.
Future<List<T>> _burst<T>(int count, Future<T> Function() read, _Gate gate) {
  final List<Future<T>> reads = <Future<T>>[
    for (var i = 0; i < count; i++) read(),
  ];
  return Future<void>.delayed(Duration.zero).then((_) {
    gate.open();
    return Future.wait(reads);
  });
}

void main() {
  late DateTime clock;
  setUp(() => clock = DateTime.utc(2026, 10, 12, 20));

  group('CachedFixtureScoreRepository', () {
    test('a burst for one fixture reaches the database once', () async {
      final _GatedScores inner = _GatedScores();
      final CachedFixtureScoreRepository scores = CachedFixtureScoreRepository(
        inner,
        now: () => clock,
      );
      final List<Result<List<ParticipantFixtureScore>>> answers = await _burst(
        170,
        () => scores.listByFixture(const FixtureRef(_f1)),
        inner.gate,
      );
      expect(inner.gate.reads, 1);
      expect(
        answers.every((answer) => answer is Ok<List<ParticipantFixtureScore>>),
        isTrue,
      );
      await scores.listByFixture(const FixtureRef(_f1));
      expect(inner.gate.reads, 1, reason: 'then served from memory');
    });

    test('two fixtures load separately', () async {
      final _GatedScores inner = _GatedScores();
      final CachedFixtureScoreRepository scores = CachedFixtureScoreRepository(
        inner,
        now: () => clock,
      );
      final Future<List<Result<List<ParticipantFixtureScore>>>> first = _burst(
        5,
        () => scores.listByFixture(const FixtureRef(_f1)),
        inner.gate,
      );
      await scores.listByFixture(const FixtureRef(_f2));
      await first;
      expect(inner.gate.reads, 2);
    });

    test('the day board batch is shared while it loads', () async {
      final _GatedScores inner = _GatedScores();
      final CachedFixtureScoreRepository scores = CachedFixtureScoreRepository(
        inner,
        now: () => clock,
      );
      await _burst(
        40,
        () => scores.listBySeasonFixtures(const <FixtureRef>[
          FixtureRef(_f2),
          FixtureRef(_f1),
        ]),
        inner.gate,
      );
      expect(inner.batchReads, 1);
      await scores.listBySeasonFixtures(const <FixtureRef>[FixtureRef(_f1)]);
      expect(inner.batchReads, 2, reason: 'the batch itself is not cached');
    });
  });

  group('CachedFixtureResultReads', () {
    test('a burst for one result reaches the database once, and "no result '
        'yet" is kept for the ttl', () async {
      final _GatedResults inner = _GatedResults();
      final CachedFixtureResultReads results = CachedFixtureResultReads(
        inner,
        now: () => clock,
      );
      await _burst(
        170,
        () => results.findByFixture(const FixtureRef(_f1)),
        inner.gate,
      );
      expect(inner.gate.reads, 1);
      final Result<FixtureResult?> again = await results.findByFixture(
        const FixtureRef(_f1),
      );
      expect(inner.gate.reads, 1);
      expect((again as Ok<FixtureResult?>).value, isNull);
      clock = clock.add(const Duration(minutes: 30));
      await results.findByFixture(const FixtureRef(_f1));
      expect(inner.gate.reads, 2, reason: 'expired after the ttl');
    });

    test('a failure is not kept', () async {
      final _GatedResults inner = _GatedResults()..next = _down;
      final CachedFixtureResultReads results = CachedFixtureResultReads(
        inner,
        now: () => clock,
      );
      inner.gate.open();
      await results.findByFixture(const FixtureRef(_f1));
      inner.next = const Result.ok(null);
      await results.findByFixture(const FixtureRef(_f1));
      expect(inner.gate.reads, 2);
    });

    test('the day board results are shared and kept', () async {
      final _GatedResults inner = _GatedResults();
      final CachedFixtureResultReads results = CachedFixtureResultReads(
        inner,
        now: () => clock,
      );
      await _burst(
        40,
        () => results.findByFixtures(const <FixtureRef>[
          FixtureRef(_f1),
          FixtureRef(_f2),
        ]),
        inner.gate,
      );
      await results.findByFixtures(const <FixtureRef>[
        FixtureRef(_f2),
        FixtureRef(_f1),
      ]);
      expect(inner.gate.reads, 1, reason: 'the same set in any order');
    });
  });

  group('CachedFixturePredictionReads', () {
    test('a burst for one season link reaches the database once', () async {
      final _GatedPredictions inner = _GatedPredictions();
      final CachedFixturePredictionReads reads = CachedFixturePredictionReads(
        inner,
        now: () => clock,
      );
      await _burst(
        170,
        () =>
            reads.findSeasonFixture(const SeasonId(_s1), const FixtureRef(_f1)),
        inner.linkGate,
      );
      await reads.findSeasonFixture(const SeasonId(_s1), const FixtureRef(_f1));
      expect(inner.linkGate.reads, 1);
    });

    test('an unlink drops the cached links', () async {
      final _GatedPredictions inner = _GatedPredictions();
      final CachedFixturePredictionReads reads = CachedFixturePredictionReads(
        inner,
        now: () => clock,
      );
      inner.linkGate.open();
      await reads.findSeasonFixture(const SeasonId(_s1), const FixtureRef(_f1));
      await reads.unlinkFixtureFromSeason(
        seasonId: const SeasonId(_s1),
        fixture: const FixtureRef(_f1),
      );
      await reads.findSeasonFixture(const SeasonId(_s1), const FixtureRef(_f1));
      expect(inner.unlinks, 1);
      expect(inner.linkGate.reads, 2);
    });

    test(
      'a burst for one fixture\'s predictions reaches the database once',
      () async {
        final _GatedPredictions inner = _GatedPredictions();
        final CachedFixturePredictionReads reads = CachedFixturePredictionReads(
          inner,
          now: () => clock,
        );
        await _burst(
          170,
          () => reads.listByFixture(const FixtureRef(_f1)),
          inner.listGate,
        );
        expect(inner.listGate.reads, 1);
      },
    );

    test('a season\'s fixtures: one query for a burst, kept for a minute '
        '(script 138)', () async {
      final _GatedPredictions inner = _GatedPredictions();
      final CachedFixturePredictionReads reads = CachedFixturePredictionReads(
        inner,
        now: () => clock,
      );
      final List<Result<List<FixtureRef>>> burst = await _burst(
        170,
        () => reads.listSeasonFixtures(const SeasonId(_s1)),
        inner.seasonGate,
      );
      expect(
        (burst.last as Ok<List<FixtureRef>>).value.map((f) => f.value),
        <String>[_f1, _f2],
      );
      clock = clock.add(const Duration(seconds: 59));
      await reads.listSeasonFixtures(const SeasonId(_s1));
      expect(inner.seasonGate.reads, 1);
      clock = clock.add(const Duration(seconds: 2));
      await reads.listSeasonFixtures(const SeasonId(_s1));
      expect(inner.seasonGate.reads, 2);
    });

    test('a link or an unlink drops the season\'s fixtures', () async {
      final _GatedPredictions inner = _GatedPredictions();
      final CachedFixturePredictionReads reads = CachedFixturePredictionReads(
        inner,
        now: () => clock,
      );
      inner.seasonGate.open();
      await reads.listSeasonFixtures(const SeasonId(_s1));
      await reads.unlinkFixtureFromSeason(
        seasonId: const SeasonId(_s1),
        fixture: const FixtureRef(_f1),
      );
      await reads.listSeasonFixtures(const SeasonId(_s1));
      final Result<SeasonFixture> link = SeasonFixture.create(
        seasonId: const SeasonId(_s1),
        fixture: const FixtureRef(_f2),
        displayOrder: 0,
      );
      await reads.linkFixtureToSeason((link as Ok<SeasonFixture>).value);
      await reads.listSeasonFixtures(const SeasonId(_s1));
      expect(inner.seasonGate.reads, 3);
    });

    test('the other reads pass straight through', () async {
      final _GatedPredictions inner = _GatedPredictions();
      final CachedFixturePredictionReads reads = CachedFixturePredictionReads(
        inner,
        now: () => clock,
      );
      await reads.listByUser(
        const UserId('aaaaaaaa-0000-0000-0000-000000000001'),
      );
      await reads.listByUser(
        const UserId('aaaaaaaa-0000-0000-0000-000000000001'),
      );
      expect(inner.userReads, 2);
    });
  });

  group('CachedFixtureScheduleRepository', () {
    test('a burst for one batch reaches the database once', () async {
      final _GatedSchedules inner = _GatedSchedules();
      final CachedFixtureScheduleRepository schedules =
          CachedFixtureScheduleRepository(inner, now: () => clock);
      await _burst(
        170,
        () => schedules.findByFixtures(const <FixtureRef>[FixtureRef(_f1)]),
        inner.gate,
      );
      expect(inner.gate.reads, 1);
    });

    test('a read after a write does not join a load begun before it', () async {
      final _GatedSchedules inner = _GatedSchedules();
      final CachedFixtureScheduleRepository schedules =
          CachedFixtureScheduleRepository(inner, now: () => clock);
      final Future<Result<List<FixtureSchedule>>> before = schedules
          .findByFixtures(const <FixtureRef>[FixtureRef(_f1)]);
      await Future<void>.delayed(Duration.zero);
      schedules.forget();
      final Future<Result<List<FixtureSchedule>>> after = schedules
          .findByFixtures(const <FixtureRef>[FixtureRef(_f1)]);
      await Future<void>.delayed(Duration.zero);
      inner.gate.open();
      await Future.wait(<Future<Result<List<FixtureSchedule>>>>[before, after]);
      expect(inner.gate.reads, 2);
    });
  });
}

final class _GatedSchedules implements FixtureScheduleRepository {
  final _Gate gate = _Gate();

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    await gate.pass();
    return const Result.ok(<FixtureSchedule>[]);
  }

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async =>
      const Result.ok(null);
}
