import 'package:application/src/admin/audit_recorder.dart';
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
/// Unlike [AdminListRoundPredictions] (gated on `RoundStatus.scored`, so the
/// round report's raw half and score half become available together), this
/// deliberately carries NO fixture-status gate — mirroring `GetFixtureScores`'
/// Option-3 live/partial philosophy: an admin may inspect predictions before
/// or after scoring, and an empty list is a legitimate result, not an error.
///
/// Steps:
/// 1. authorize the caller as [PlatformRole.admin];
/// 2. parse the fixture id;
/// 3. record an immutable [AuditEntry] (`fixture_predictions_viewed`) BEFORE
///    returning the data;
/// 4. return every [FixturePredictionView] for the fixture.
///
/// Never throws; returns a typed [Result].
final class AdminListFixturePredictions {
  /// Creates the use-case over its collaborators.
  const AdminListFixturePredictions({
    required FixturePredictionRepository fixturePredictionRepository,
    required AuditRecorder auditRecorder,
  }) : _predictions = fixturePredictionRepository,
       _audit = auditRecorder;

  final FixturePredictionRepository _predictions;
  final AuditRecorder _audit;

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
