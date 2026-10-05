import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the Duels surface of `apps/server` (migration 0090).
///
/// Wraps the routes verbatim:
///   * `POST /duels/challenges` -> `201` [DuelChallengeDto]
///     (`routes/duels/challenges/index.dart`).
///   * `POST /duels/challenges/{id}/accept` -> [DuelDto].
///   * `POST /duels/challenges/{id}/cancel` -> `{"status": "cancelled"}`.
///   * `POST /duels/challenges/{id}/decline` -> `{"status": "declined"}`.
///   * `GET  /duels/codes/{code}` -> [DuelChallengeDto].
///   * `GET  /me/duels` -> [MyDuelsDto].
///   * `GET  /duels/players?q=` -> [DuelPlayersDto].
///
/// Every rule (the prediction required before a challenge, the 30-minute
/// lead time, capacity, the private target, one duel per pair) is decided
/// server-side and by the database; this client decides nothing. A refusal
/// arrives as an ordinary `Err` with the server's `social.*` code. Every
/// method returns a typed [Result] and never throws.
final class DuelsApi {
  /// Creates the Duels client over the shared [ApiTransport].
  const DuelsApi(this._transport);

  final ApiTransport _transport;

  /// `POST /duels/challenges` -- challenges on [fixtureId]. Without
  /// [targetUserId] it is open (the server default capacity unless
  /// [capacity] is given); with one it is private, for that player only.
  Future<Result<DuelChallengeDto>> createChallenge({
    required String seasonId,
    required String fixtureId,
    int? capacity,
    String? targetUserId,
  }) {
    return _transport.postObject<DuelChallengeDto>(
      '/duels/challenges',
      body: CreateDuelChallengeRequestDto(
        seasonId: seasonId,
        fixtureId: fixtureId,
        capacity: capacity,
        targetUserId: targetUserId,
      ).toJson(),
      parse: DuelChallengeDto.fromJson,
    );
  }

  /// `POST /duels/challenges/{challengeId}/accept` -- accepts with the
  /// caller's own prediction, which the server saves first.
  Future<Result<DuelDto>> acceptChallenge(
    String challengeId, {
    required int homeGoals,
    required int awayGoals,
    bool isDouble = false,
  }) {
    return _transport.postObject<DuelDto>(
      '/duels/challenges/${Uri.encodeComponent(challengeId)}/accept',
      body: AcceptDuelChallengeRequestDto(
        homeGoals: homeGoals,
        awayGoals: awayGoals,
        isDouble: isDouble,
      ).toJson(),
      parse: DuelDto.fromJson,
    );
  }

  /// `POST /duels/challenges/{challengeId}/cancel` -- the challenger closes
  /// it. Answers the new state, `cancelled`.
  Future<Result<String>> cancelChallenge(String challengeId) {
    return _transport.postObject<String>(
      '/duels/challenges/${Uri.encodeComponent(challengeId)}/cancel',
      body: const {},
      parse: _status,
    );
  }

  /// `POST /duels/challenges/{challengeId}/decline` -- the invited player
  /// refuses a private challenge. Answers the new state, `declined`.
  Future<Result<String>> declineChallenge(String challengeId) {
    return _transport.postObject<String>(
      '/duels/challenges/${Uri.encodeComponent(challengeId)}/decline',
      body: const {},
      parse: _status,
    );
  }

  /// `GET /duels/codes/{code}` -- opens a shared duel link.
  Future<Result<DuelChallengeDto>> challengeByCode(String code) {
    return _transport.getObject<DuelChallengeDto>(
      '/duels/codes/${Uri.encodeComponent(code.trim().toUpperCase())}',
      parse: DuelChallengeDto.fromJson,
    );
  }

  /// `GET /me/duels` -- the caller's open challenges and duels.
  Future<Result<MyDuelsDto>> myDuels() {
    return _transport.getObject<MyDuelsDto>(
      '/me/duels',
      parse: MyDuelsDto.fromJson,
    );
  }

  /// `GET /duels/players?q=NAME` -- players to challenge by name. The
  /// server answers nothing for fewer than two characters.
  Future<Result<DuelPlayersDto>> searchPlayers(String query) {
    return _transport.getObject<DuelPlayersDto>(
      '/duels/players',
      query: {'q': query.trim()},
      parse: DuelPlayersDto.fromJson,
    );
  }

  static String _status(Map<String, Object?> json) {
    final status = json['status'];
    return status is String ? status : '';
  }
}
