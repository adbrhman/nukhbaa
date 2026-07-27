import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the caller's own Ledger surface of `apps/server`.
///
/// Wraps exactly the two self-read routes that exist today, verbatim — no
/// invented path:
///   * `GET /participants/{id}/balance` -> [BalanceDto]
///     (`routes/participants/[id]/balance/index.dart`).
///   * `GET /participants/{id}/entries` -> [ParticipantEntriesDto]
///     (`routes/participants/[id]/entries/index.dart`).
///
/// A ledger is a **read-only** projection over the append-only `PointEntry`
/// stream (Axiom 5): the server computes every balance and entry; the client
/// never submits or computes a point value, so there is deliberately no
/// command method here.
///
/// Visibility gate (server-side, `ReadParticipantLedger`): **ownership** — a
/// caller may read only a participant they own. A missing participant, or one
/// owned by someone else, is reported identically as `401`
/// `ledger.participant_not_found`, which surfaces here as
/// `Err(authorization, code: ledger.participant_not_found)` — never an
/// enumeration/ownership oracle.
///
/// The whole `/participants` subtree is already behind `bearerAuth`
/// (`routes/participants/_middleware.dart`); an unauthenticated call is
/// refused there with `401`. Every method is a pure read, returns a typed
/// [Result], and never throws.
final class LedgerApi {
  /// Creates the Ledger client over the shared [ApiTransport].
  const LedgerApi(this._transport);

  final ApiTransport _transport;

  /// `GET /participants/{participantId}/balance` — the participant's
  /// projected balance over their own ledger stream.
  Future<Result<BalanceDto>> balanceOf(String participantId) {
    return _transport.getObject<BalanceDto>(
      '/participants/$participantId/balance',
      parse: BalanceDto.fromJson,
    );
  }

  /// `GET /participants/{participantId}/entries` — the participant's
  /// append-only entry stream, oldest first. An empty list is a legitimate
  /// result (no movements yet), never an error.
  Future<Result<ParticipantEntriesDto>> entriesOf(String participantId) {
    return _transport.getObject<ParticipantEntriesDto>(
      '/participants/$participantId/entries',
      parse: ParticipantEntriesDto.fromJson,
    );
  }
}
