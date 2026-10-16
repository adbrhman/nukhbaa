import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/competition/register_fixture_schedule.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/rescore_earlier_kickoff.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: correct an already-registered fixture's identity (team names,
/// enrichment ids) and, while it is still permitted, its kickoff time.
///
/// **Why the kickoff is special.** The prediction lock is derived entirely
/// from `fixture_schedules.kickoff_at`: `SubmitFixturePrediction` refuses once
/// `now >= kickoffAt`, and migration 0029 enforces the same rule in the
/// database. Moving that column therefore moves the deadline. An admin who
/// pushed the kickoff of a match that had already been played into the future
/// would re-open the lock on a fixture whose result is public knowledge.
///
/// **The freeze rule.** The kickoff may be put back only while the *stored*
/// kickoff is still in the future. Once it has passed, a later time is
/// refused as `competition.kickoff_frozen`. A genuine data-entry mistake is
/// still fixable right up to the moment the match starts; a retroactive
/// re-opening is impossible. Every other field stays correctable at any
/// time — a misspelt team name carries no competitive consequence.
///
/// **Brought forward (audit C-03).** An earlier kickoff never re-opens the
/// lock, so it is accepted even after the stored one passed: a match that
/// really started earlier than stored is then locked from its real kickoff,
/// and `ScoreFixture` gives nothing to a prediction sent after it. A fixture
/// already scored is scored again ([RescoreEarlierKickoff]); if that fails,
/// the kickoff stays moved and the admin is told to score it again.
///
/// **The audit trace.** Every correction records an immutable
/// [AuditAction.fixtureScheduleCorrected] entry naming the actor, the fixture,
/// and — when the kickoff moved — its old and new values. The entry is written
/// AFTER a successful persist (mirroring `SuspendUser`), and a failure to
/// record it propagates: a crown-jewel admin action must not succeed silently.
///
/// **Both teams from the catalog (script 93).** With [requireTeamIds] (the
/// server's root) a fixture that is not a test is refused with
/// `RegisterFixtureSchedule.teamsRequired` unless both its teams carry a
/// catalog id, as on registration.
final class CorrectFixtureSchedule {
  /// Creates the use-case over its collaborators.
  const CorrectFixtureSchedule(
    this._repository, {
    required AuditRecorder auditRecorder,
    required Clock clock,
    RescoreEarlierKickoff? rescoreEarlierKickoff,
    this.requireTeamIds = false,
  }) : _audit = auditRecorder,
       _clock = clock,
       _rescore = rescoreEarlierKickoff;

  final FixtureScheduleRepository _repository;
  final AuditRecorder _audit;
  final Clock _clock;

  /// Scores the fixture again when its kickoff is brought forward; null in
  /// the test roots, where nothing is scored again.
  final RescoreEarlierKickoff? _rescore;

  /// Whether a fixture that is not a test needs both its teams from the
  /// catalog (script 93); off in the test roots that predate it.
  final bool requireTeamIds;

  /// Corrects fixture [fixtureId] on behalf of admin [principal].
  Future<Result<FixtureSchedule>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoffAt,
    String? homeTeamId,
    String? awayTeamId,
    String? leagueId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    final homeTeamRefResult = _parseOptionalTeamRef(homeTeamId);
    if (homeTeamRefResult is Err<TeamRef?>) {
      return Result.err(homeTeamRefResult.error);
    }
    final awayTeamRefResult = _parseOptionalTeamRef(awayTeamId);
    if (awayTeamRefResult is Err<TeamRef?>) {
      return Result.err(awayTeamRefResult.error);
    }

    final leagueRefResult = _parseOptionalLeagueRef(leagueId);
    if (leagueRefResult is Err<LeagueRef?>) {
      return Result.err(leagueRefResult.error);
    }

    // The stored row is read BEFORE validating the new one: the freeze rule
    // reasons about the kickoff already on file, not the one being proposed.
    final existingResult = await _repository.findByFixture(fixture);
    if (existingResult is Err<FixtureSchedule?>) {
      return Result.err(existingResult.error);
    }
    final existing = (existingResult as Ok<FixtureSchedule?>).value;

    if (requireTeamIds &&
        !(existing?.isTest ?? false) &&
        (homeTeamId == null || awayTeamId == null)) {
      return const Result.err(RegisterFixtureSchedule.teamsRequired);
    }

    final DateTime? previousKickoff = existing?.kickoffAt.toUtc();
    final DateTime nextKickoff = kickoffAt.toUtc();
    final bool kickoffMoved =
        previousKickoff != null &&
        !previousKickoff.isAtSameMomentAs(nextKickoff);
    // Earlier never re-opens the lock (C-03): only a later kickoff freezes.
    final bool broughtForward =
        previousKickoff != null && nextKickoff.isBefore(previousKickoff);

    if (previousKickoff != null &&
        kickoffMoved &&
        !broughtForward &&
        !previousKickoff.isAfter(_clock.nowUtc())) {
      return Result.err(
        AppError.invariant(
          'competition.kickoff_frozen',
          'Fixture ${fixture.value} has already kicked off at '
              '${previousKickoff.toIso8601String()}; its kickoff time can no '
              'longer be changed',
        ),
      );
    }

    final scheduleResult = FixtureSchedule.create(
      fixture: fixture,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoffAt: kickoffAt,
      homeTeamId: (homeTeamRefResult as Ok<TeamRef?>).value,
      awayTeamId: (awayTeamRefResult as Ok<TeamRef?>).value,
      leagueId: (leagueRefResult as Ok<LeagueRef?>).value,
    );
    if (scheduleResult is Err<FixtureSchedule>) {
      return Result.err(scheduleResult.error);
    }
    final schedule = (scheduleResult as Ok<FixtureSchedule>).value;

    final saved = await _repository.upsert(schedule);
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }

    final audit = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.fixtureScheduleCorrected,
      targetRef: fixture.value,
      reason: _reason(previousKickoff, nextKickoff, kickoffMoved),
    );
    if (audit is Err<AuditEntry>) {
      return Result.err(audit.error);
    }

    // A prediction sent between the new kickoff and the old one is late now:
    // a fixture already scored is scored again.
    final rescore = _rescore;
    if (broughtForward && rescore != null) {
      final rescored = await rescore(fixture);
      if (rescored is Err<bool>) {
        return Result.err(
          AppError.transient(
            'competition.rescore_failed',
            'قُدّم الموعد، لكن تعذّرت إعادة احتساب المباراة. اضغط «احتساب '
                'المباراة» لها في «النتائج والاحتساب».',
            rescored.error,
          ),
        );
      }
    }

    return Result.ok(schedule);
  }

  /// A short, bounded description of what the correction changed, so the trail
  /// answers "what was the kickoff before?" without a second lookup.
  static String _reason(
    DateTime? previousKickoff,
    DateTime nextKickoff,
    bool kickoffMoved,
  ) {
    if (previousKickoff == null) {
      return 'kickoff set to ${nextKickoff.toIso8601String()} '
          '(no previous schedule row)';
    }
    if (!kickoffMoved) {
      return 'identity corrected; kickoff unchanged at '
          '${nextKickoff.toIso8601String()}';
    }
    return 'kickoff moved from ${previousKickoff.toIso8601String()} '
        'to ${nextKickoff.toIso8601String()}';
  }

  /// Parses an optional client-supplied league id: absent stays absent (the
  /// enrichment is opt-in), present must be a valid [LeagueRef].
  static Result<LeagueRef?> _parseOptionalLeagueRef(String? raw) {
    if (raw == null) {
      return const Result.ok(null);
    }
    final parsed = LeagueRef.tryParse(raw);
    return switch (parsed) {
      Ok<LeagueRef>(:final value) => Result.ok(value),
      Err<LeagueRef>(:final error) => Result.err(error),
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
