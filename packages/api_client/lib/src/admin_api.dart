import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the Admin Panel surface of `apps/server`.
///
/// Wraps the ratified routes verbatim — no invented path:
///   * `GET  /admin/audit` -> [AuditLogDto] (`routes/admin/audit/index.dart`).
///   * `POST /admin/users/{id}/suspend` -> [UserSanctionResultDto]
///     (`routes/admin/users/[id]/suspend/index.dart`).
///   * `POST /admin/users/{id}/reinstate` -> [UserSanctionResultDto]
///     (`routes/admin/users/[id]/reinstate/index.dart`).
///   * `GET  /admin/participants/{id}/ledger` -> [ParticipantEntriesDto]
///     (`routes/admin/participants/[id]/ledger/index.dart`).
///
/// **Admin-only**, enforced entirely inside the server use-cases (Security ADR
/// §2.2/§2.3) — this client makes no authorization decision of its own; a
/// non-admin caller is refused `401 auth.insufficient_role` with no oracle.
///
/// The cross-user ledger read is deliberately narrow (Admin Panel decision
/// OPEN-A #3): a single participant by explicit id, read-only, and the read
/// is itself audited server-side before it is served.
///
/// The whole `/admin` subtree is already behind `bearerAuth`
/// (`routes/admin/_middleware.dart`); an unauthenticated call is refused there
/// with `401`. Every method returns a typed [Result] and never throws.
final class AdminApi {
  /// Creates the Admin client over the shared [ApiTransport].
  const AdminApi(this._transport);

  final ApiTransport _transport;

  /// `GET /admin/audit` — the append-only audit trail, newest first. [limit]
  /// is an optional page cap; the server clamps an untrusted value rather
  /// than rejecting it.
  Future<Result<AuditLogDto>> listAuditLog({int? limit}) {
    return _transport.getObject<AuditLogDto>(
      '/admin/audit',
      query: limit == null ? null : {'limit': '$limit'},
      parse: AuditLogDto.fromJson,
    );
  }

  /// `GET /admin/users` — browse users by an optional email-contains
  /// [search]; [limit] is an optional page cap, clamped server-side.
  Future<Result<UserListDto>> listUsers({String? search, int? limit}) {
    final query = <String, String>{
      if (search != null && search.isNotEmpty) 'search': search,
      if (limit != null) 'limit': '$limit',
    };
    return _transport.getObject<UserListDto>(
      '/admin/users',
      query: query.isEmpty ? null : query,
      parse: UserListDto.fromJson,
    );
  }

  /// `POST /admin/users/{userId}/suspend` — suspends a user, with a
  /// mandatory [reason] recorded on the audit trail. Idempotent: re-suspending
  /// an already-suspended user converges and echoes `suspended`.
  Future<Result<UserSanctionResultDto>> suspendUser(
    String userId,
    String reason,
  ) {
    return _transport.postObject<UserSanctionResultDto>(
      '/admin/users/$userId/suspend',
      body: SuspendUserRequestDto(reason: reason).toJson(),
      parse: UserSanctionResultDto.fromJson,
    );
  }

  /// `POST /admin/users/{userId}/reinstate` — reverses a suspension, with a
  /// mandatory [reason] recorded on the audit trail (equally attributable as
  /// the sanction itself).
  Future<Result<UserSanctionResultDto>> reinstateUser(
    String userId,
    String reason,
  ) {
    return _transport.postObject<UserSanctionResultDto>(
      '/admin/users/$userId/reinstate',
      body: SuspendUserRequestDto(reason: reason).toJson(),
      parse: UserSanctionResultDto.fromJson,
    );
  }

  /// `GET /admin/participants/{participantId}/ledger` — a support-read of a
  /// SINGLE participant's ledger by explicit id. [reason] is an optional
  /// justification recorded on the (mandatory) audit entry for this read; the
  /// read itself is always audited server-side regardless of whether one is
  /// supplied.
  Future<Result<ParticipantEntriesDto>> viewParticipantLedger(
    String participantId, {
    String? reason,
  }) {
    return _transport.getObject<ParticipantEntriesDto>(
      '/admin/participants/$participantId/ledger',
      query: reason == null ? null : {'reason': reason},
      parse: ParticipantEntriesDto.fromJson,
    );
  }

  /// `GET /admin/rounds/{roundId}/predictions` — the round-report bulk read:
  /// every participant's raw predicted scorelines for a **scored** round.
  /// [reason] is an optional justification recorded on the (mandatory) audit
  /// entry for this read; the read itself is always audited server-side
  /// regardless of whether one is supplied.
  Future<Result<List<PredictionDto>>> adminListRoundPredictions(
    String roundId, {
    String? reason,
  }) {
    return _transport.getList<PredictionDto>(
      '/admin/rounds/$roundId/predictions',
      query: reason == null ? null : {'reason': reason},
      parseElement: PredictionDto.fromJson,
    );
  }

  /// `GET /admin/rounds/{roundId}/scores` — بلا شرط مشاركة الموسم.
  Future<Result<RoundScoresDto>> adminGetRoundScores(String roundId) {
    return _transport.getObject<RoundScoresDto>(
      '/admin/rounds/$roundId/scores',
      parse: RoundScoresDto.fromJson,
    );
  }

  /// `GET /admin/rounds/{roundId}/report` — بلا شرط مشاركة الموسم.
  Future<Result<RoundReportDto>> adminGetRoundReport(String roundId) {
    return _transport.getObject<RoundReportDto>(
      '/admin/rounds/$roundId/report',
      parse: RoundReportDto.fromJson,
    );
  }
}
