import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class CorrectFixtureSchedule {
  const CorrectFixtureSchedule(this._repository);

  final FixtureScheduleRepository _repository;

  Future<Result<FixtureSchedule>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoffAt,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }

    final scheduleResult = FixtureSchedule.create(
      fixture: (fixtureResult as Ok<FixtureRef>).value,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoffAt: kickoffAt,
    );
    if (scheduleResult is Err<FixtureSchedule>) {
      return Result.err(scheduleResult.error);
    }
    final schedule = (scheduleResult as Ok<FixtureSchedule>).value;

    final saved = await _repository.upsert(schedule);
    return switch (saved) {
      Ok<void>() => Result.ok(schedule),
      Err<void>(:final error) => Result.err(error),
    };
  }
}
