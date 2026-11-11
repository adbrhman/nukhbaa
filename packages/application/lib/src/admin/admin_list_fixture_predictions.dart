import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the admin **fixture raw-predictions read** — every
/// participant's predicted scorelines for one fixture (Admin Panel decision
/// OPEN-A #3 lineage: read-only, scoped to a single fixture by explicit id,
/// itself audited — mirrors [AdminListRoundPredictions] and
/// [ViewParticipantLedger]).
///
/// **Sealed until kickoff, for the admins too** (decided by the owner on
/// 2026-11-11, script 261): the admins play like any player, so this read
/// opens at the same instant as the players' own ([ListFixturePredictions]):
/// [FixtureLock] over the fixture's schedule and the server [Clock]. Before
/// it, or for a fixture with no kickoff, the answer is the players' own
/// refusal, `prediction.fixture_not_started` ([ErrorKind.invariant]), and
/// nothing is audited because nothing is read. After it, an admin may
/// inspect the predictions before or after scoring, and an empty list is a
/// legitimate result, not an error.
///
/// Steps:
/// 1. authorize the caller as [PlatformRole.admin];
/// 2. parse the fixture id;
/// 3. refuse a fixture that has not kicked off;
/// 4. record an immutable [AuditEntry] (`fixture_predictions_viewed`) BEFORE
///    returning the data;
/// 5. return every [FixturePredictionView] for the fixture.
///
/// Never throws; returns a typed [Result].
final class AdminListFixturePredictions {
  /// Creates the use-case over its collaborators.
  const AdminListFixturePredictions({
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required AuditRecorder auditRecorder,
    required Clock clock,
  }) : _predictions = fixturePredictionRepository,
       _schedules = fixtureScheduleRepository,
       _audit = auditRecorder,
       _clock = clock;

  final FixturePredictionRepository _predictions;
  final FixtureScheduleRepository _schedules;
  final AuditRecorder _audit;
  final Clock _clock;

  /// The refusal before kickoff: the players' own
  /// (`ListFixturePredictions`), so every client already words it.
  static const AppError sealed = AppError.invariant(
    'prediction.fixture_not_started',
    'Predictions stay hidden until the fixture kicks off',
  );

  /// Returns every participant's raw prediction for [fixtureId], recording
  /// the bulk support read in the audit trail.
  Future<Result<List<FixturePredictionView>>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
    String? reason,
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

    final schedulesResult = await _schedules.findByFixtures([fixture]);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final schedules = (schedulesResult as Ok<List<FixtureSchedule>>).value;
    if (schedules.isEmpty) {
      return const Result.err(sealed);
    }
    final lock = FixtureLock.at(
      kickoffAt: schedules.first.kickoffAt.toUtc(),
      nowUtc: _clock.nowUtc(),
    );
    if (lock is Err<FixtureLock>) {
      return Result.err(lock.error);
    }
    if (!(lock as Ok<FixtureLock>).value.isLocked) {
      return const Result.err(sealed);
    }

    // Audit the bulk cross-user read BEFORE serving the data (§2.4): a
    // completed report read always leaves an attributable trace.
    final audit = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.fixturePredictionsViewed,
      targetRef: fixture.value,
      reason: reason,
    );
    if (audit is Err<AuditEntry>) {
      return Result.err(audit.error);
    }

    return _predictions.listByFixture(fixture);
  }
}
