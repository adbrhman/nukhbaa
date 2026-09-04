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
    String? homeTeamId,
    String? awayTeamId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }

    final homeTeamRefResult = _parseOptionalTeamRef(homeTeamId);
    if (homeTeamRefResult is Err<TeamRef?>) {
      return Result.err(homeTeamRefResult.error);
    }
    final awayTeamRefResult = _parseOptionalTeamRef(awayTeamId);
    if (awayTeamRefResult is Err<TeamRef?>) {
      return Result.err(awayTeamRefResult.error);
    }

    final scheduleResult = FixtureSchedule.create(
      fixture: (fixtureResult as Ok<FixtureRef>).value,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoffAt: kickoffAt,
      homeTeamId: (homeTeamRefResult as Ok<TeamRef?>).value,
      awayTeamId: (awayTeamRefResult as Ok<TeamRef?>).value,
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

  /// Parses an optional client-supplied team id: absent stays absent (the
  /// enrichment is opt-in, Football Data phase), present must be a valid
  /// [TeamRef].
  static Result<TeamRef?> _parseOptionalTeamRef(String? raw) {
    if (raw == null) {
      return const Result.ok(null);
    }
    final parsed = TeamRef.tryParse(raw);
    return switch (parsed) {
      Ok<TeamRef>(:final value) => Result.ok(value),
      Err<TeamRef>(:final error) => Result.err(error),
    };
  }
}
