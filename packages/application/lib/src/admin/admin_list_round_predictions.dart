import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/prediction_repository.dart';
import 'package:application/src/prediction/prediction_view.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the admin **round-report raw-predictions read** — every
/// participant's predicted scorelines for one **scored** round (Admin Panel
/// decision OPEN-A #3 lineage: read-only, scoped to a single round by explicit
/// id, and itself audited — the report gets NO silent exemption from the
/// trail, mirroring [ViewParticipantLedger]).
///
/// Deliberately NOT a reuse of `ListRoundPredictions` (whose gate is
/// "caller is a participant of the round's season"): here the caller is an
/// admin who may not be a participant at all, reading every participant's
/// raw forecast at once for the round report. That widening — and the fact it
/// is bulk, not single-participant — is exactly why it is its own admin
/// use-case rather than a role bypass bolted onto the participant-facing one.
///
/// Gated on [RoundStatus.scored] (not merely locked): the round report pairs
/// this raw read with `GetRoundScores`, which uses the same gate, so both
/// halves of the report become available at the same moment and a
/// locked-but-unscored round never partially leaks.
///
/// Steps:
/// 1. authorize the caller as [PlatformRole.admin];
/// 2. resolve the round and require it is `scored`;
/// 3. record an immutable [AuditEntry] (`round_predictions_viewed`) BEFORE
///    returning the data;
/// 4. return every [PredictionView] for the round.
///
/// Never throws; returns a typed [Result].
final class AdminListRoundPredictions {
  /// Creates the use-case over its collaborators.
  const AdminListRoundPredictions({
    required CompetitionRepository competitionRepository,
    required PredictionRepository predictionRepository,
    required AuditRecorder auditRecorder,
  }) : _competition = competitionRepository,
       _predictions = predictionRepository,
       _audit = auditRecorder;

  final CompetitionRepository _competition;
  final PredictionRepository _predictions;
  final AuditRecorder _audit;

  /// Returns every participant's raw prediction for the scored round
  /// [roundId], recording the bulk support read in the audit trail.
  Future<Result<List<PredictionView>>> call({
    required AuthenticatedUser principal,
    required String roundId,
    String? reason,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final roundIdResult = RoundId.tryParse(roundId);
    if (roundIdResult is Err<RoundId>) {
      return Result.err(roundIdResult.error);
    }
    final rId = (roundIdResult as Ok<RoundId>).value;

    final roundResult = await _competition.findRound(rId);
    if (roundResult is Err<Round>) {
      return Result.err(roundResult.error);
    }
    final round = (roundResult as Ok<Round>).value;

    if (round.status != RoundStatus.scored) {
      return Result.err(
        AppError.invariant(
          'admin.round_not_scored',
          'The round report is available only after the round is scored '
              '(round is \${round.status.wireValue})',
        ),
      );
    }

    // Audit the bulk cross-user read BEFORE serving the data (§2.4): a
    // completed report read always leaves an attributable trace.
    final audit = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.roundPredictionsViewed,
      targetRef: rId.value,
      reason: reason,
    );
    if (audit is Err<AuditEntry>) {
      return Result.err(audit.error);
    }

    return _predictions.listByRound(rId);
  }
}
