import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/admin/ports/player_points_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: an admin reads one player's points in one month, picked
/// by name and month rather than by a participant id typed by hand (batch
/// 146b, audit C-01 and L-14). It replaces "سجل النقاط"'s read of
/// `ledger.point_entries`, the round ledger, empty since fixtures replaced
/// rounds, so every current player showed no movement at all.
///
/// The cross-user read stays narrow and audited as before (Admin Panel
/// decision OPEN-A #3): one player, one month, recorded as
/// `participant_ledger_viewed` before the data is served; a failed audit
/// refuses the read.
///
/// Never throws; returns a typed [Result].
final class AdminViewPlayerPoints {
  /// Creates the use-case over its collaborators.
  const AdminViewPlayerPoints({
    required PlayerPointsReader reader,
    required AuditRecorder auditRecorder,
  }) : _reader = reader,
       _audit = auditRecorder;

  final PlayerPointsReader _reader;
  final AuditRecorder _audit;

  /// The points of [userId] in [seasonId] for the admin [principal]. A
  /// player who never played in the month is an empty month, not an error.
  Future<Result<PlayerMonthPoints>> call({
    required AuthenticatedUser principal,
    required String userId,
    required String seasonId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final Result<UserId> user = UserId.tryParse(userId);
    if (user is Err<UserId>) return Result.err(user.error);
    final Result<SeasonId> season = SeasonId.tryParse(seasonId);
    if (season is Err<SeasonId>) return Result.err(season.error);

    final Result<PlayerMonthPoints> read = await _reader.pointsOf(
      user: (user as Ok<UserId>).value,
      season: (season as Ok<SeasonId>).value,
    );
    if (read is Err<PlayerMonthPoints>) return Result.err(read.error);
    final PlayerMonthPoints points = (read as Ok<PlayerMonthPoints>).value;

    final audit = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.participantLedgerViewed,
      targetRef: points.participantId ?? userId,
    );
    if (audit is Err<AuditEntry>) return Result.err(audit.error);

    return Result.ok(points);
  }
}
