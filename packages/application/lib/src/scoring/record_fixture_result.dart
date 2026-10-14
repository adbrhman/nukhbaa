import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: record the actual final score of a fixture (Application ADR,
/// Section 2: command intent `RecordFixtureResult`).
///
/// This is the admin ingestion command behind the Axiom-3 football seam
/// (Next-Task decision 2026-07-11, option (a)): the platform has no
/// Football-Data phase before Scoring, so the actual scoreline enters through
/// this minimal admin command rather than an automated feed. The client never
/// submits a result (Axioms 2/5 integrity boundary): the caller must hold the
/// **admin** platform role, and a fixture result carries no competition/round
/// reference — the same result may feed many rounds (Axiom 3).
///
/// Idempotent (Application ADR, Section 2): recording a result for a fixture
/// upserts in place, so an admin can correct a mistyped scoreline before the
/// round is scored, and a retried call converges on the same stored value.
///
/// **Audited** (audit M-25): a result an admin records or corrects decides
/// points, boards and the crown, so it leaves `fixture_result_recorded` in
/// `admin.audit_log` with the admin and the score before and after
/// (`2-1`, or `1-1 -> 2-1` for a correction). The provider sync records
/// under the service principal, which is not a user, and is not audited:
/// its source is the feed itself.
///
/// Never throws; returns a typed [Result].
final class RecordFixtureResult {
  /// Creates the use-case over its collaborators.
  const RecordFixtureResult({
    required FixtureResultRepository resultRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required Clock clock,
    AuditRecorder? auditRecorder,
  }) : _results = resultRepository,
       _fixtureSchedules = fixtureScheduleRepository,
       _clock = clock,
       _audit = auditRecorder;

  final FixtureResultRepository _results;
  final FixtureScheduleRepository _fixtureSchedules;
  final Clock _clock;
  final AuditRecorder? _audit;

  /// Records that [fixtureId] finished [homeGoals]–[awayGoals], on behalf of the
  /// admin [principal]. Validates the id and the scoreline (via the domain
  /// [FixtureResult.create]) before touching storage.
  Future<Result<FixtureResult>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
    required int homeGoals,
    required int awayGoals,
  }) async {
    // Layer 1: only an admin may ingest actual results (Axioms 2/5).
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    // Domain validation: non-negative, within the shared goal ceiling.
    final resultResult = FixtureResult.create(
      fixture: fixture,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
    );
    if (resultResult is Err<FixtureResult>) {
      return Result.err(resultResult.error);
    }
    final result = (resultResult as Ok<FixtureResult>).value;

    // A result is a fact about a match that has been played. While the
    // fixture's registered kickoff is still ahead it is refused: recording
    // one early scores every open prediction against a scoreline that has
    // not happened, and the fixture stays open for predictions after it.
    final now = _clock.nowUtc();
    final schedulesResult = await _fixtureSchedules.findByFixtures([fixture]);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final schedules = (schedulesResult as Ok<List<FixtureSchedule>>).value;
    if (schedules.isNotEmpty && schedules.first.kickoffAt.isAfter(now)) {
      return Result.err(
        AppError.invariant(
          'scoring.fixture_not_started',
          'Fixture ${fixture.value} has not kicked off yet; its result '
              'cannot be recorded before kickoff',
        ),
      );
    }

    // The score before, for the audit trail; a failed read only loses the
    // "before" half of the reason, never the recording.
    final AuditRecorder? audit = principal.role == PlatformRole.admin
        ? _audit
        : null;
    FixtureResult? previous;
    if (audit != null) {
      final before = await _results.findByFixture(fixture);
      if (before is Ok<FixtureResult?>) previous = before.value;
    }

    final saved = await _results.upsert(result, now);
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }

    if (audit != null) {
      final recorded = await audit.record(
        actorId: principal.userId,
        action: AuditAction.fixtureResultRecorded,
        targetRef: fixture.value,
        reason: previous == null
            ? _score(result)
            : '${_score(previous)} -> ${_score(result)}',
      );
      if (recorded is Err<AuditEntry>) {
        return Result.err(recorded.error);
      }
    }
    return Result.ok(result);
  }

  static String _score(FixtureResult result) =>
      '${result.homeGoals}-${result.awayGoals}';
}
