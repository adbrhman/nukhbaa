import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A minimal in-memory [FixtureScheduleRepository] for the prediction
/// use-case tests. With nothing seeded, [findByFixtures] returns an empty
/// list for any request, so [SubmitPrediction] treats every fixture as NOT
/// yet kicked off — matching this suite's pre-existing "covers the whole
/// round" fixtures, none of which model a per-fixture kickoff lock.
final class FakeFixtureScheduleRepository implements FixtureScheduleRepository {
  final Map<String, FixtureSchedule> _byFixture = {};

  void seed(FixtureSchedule schedule) =>
      _byFixture[schedule.fixture.value] = schedule;

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async {
    _byFixture[schedule.fixture.value] = schedule;
    return const Result.ok(null);
  }

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) async =>
      Result.ok(_byFixture[fixture.value]);

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    final found = <FixtureSchedule>[
      for (final f in fixtures)
        if (_byFixture[f.value] != null) _byFixture[f.value]!,
    ];
    return Result.ok(found);
  }
}
