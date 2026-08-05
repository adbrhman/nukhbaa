import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

abstract interface class FixtureScheduleRepository {
  Future<Result<void>> upsert(FixtureSchedule schedule);

  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture);

  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  );
}
