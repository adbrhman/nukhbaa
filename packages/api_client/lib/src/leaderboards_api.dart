import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the Leaderboards surface of `apps/server`.
///
/// Wraps the ratified leaderboard read routes, verbatim — no invented path:
///   * `GET /seasons/{id}/leaderboard` -> [SeasonLeaderboardDto]
///     (`routes/seasons/[id]/leaderboard/index.dart`).
///   * `GET /rounds/{id}/leaderboard` -> [RoundLeaderboardDto]
///     (`routes/rounds/[id]/leaderboard/index.dart`).
///   * `GET /leaderboard/hall-of-fame` -> [HallOfFameDto]
///     (`routes/leaderboard/hall-of-fame/index.dart`).
///
/// A leaderboard is a **read-only** projection over the append-only ledger
/// (Axiom 5): the server computes every rank and total; the client never
/// submits or computes a point value, so this client is query-only (there is no
/// command DTO for a leaderboard — contracts `leaderboard_dto.dart`).
///
/// Visibility gate (server-side, `GetSeasonLeaderboard`): the season standings
/// are visible only to a **member of the season** (any status — a withdrawn
/// member keeps their record and may still read the board they were part of).
/// A non-member is refused `401 leaderboard.not_a_participant`, which surfaces
/// here as `Err(authorization, code: leaderboard.not_a_participant)`; the board
/// is therefore not a season-existence oracle beyond membership (Security ADR
/// §2). The Hall of Fame (`GetHallOfFame`) carries no such gate — it is
/// intentionally visible to any authenticated user.
///
/// Both subtrees are behind `bearerAuth`; an unauthenticated call is refused
/// there with `401`. Every method is a pure read (no side effect), returns a
/// typed [Result], and never throws.
///
/// Group leaderboards (`GET /groups/{id}/seasons/{seasonId}/leaderboard`) are
/// wrapped by `GroupsApi.leaderboard`, not here — that read is member-of-group
/// scoped, a different visibility gate from either surface in this client.
final class LeaderboardsApi {
  /// Creates the Leaderboards client over the shared [ApiTransport].
  const LeaderboardsApi(this._transport);

  final ApiTransport _transport;

  /// `GET /seasons/{id}/leaderboard` — a season's ranked standings.
  ///
  /// Returns:
  ///   * `Ok(SeasonLeaderboardDto)` on `200` — an **empty** `entries` list is a
  ///     legitimate result (a season with no participants), never an error;
  ///   * `Err(authorization, code: leaderboard.not_a_participant)` on `401`
  ///     when the caller is not a member of the season;
  ///   * `Err(validation)` if [seasonId] is malformed (server `400`);
  ///   * `Err(transient)` on `503` or a network failure (retryable);
  ///   * `Err(validation, code: api_client.malformed_response)` if the `200`
  ///     body is not a valid [SeasonLeaderboardDto].
  Future<Result<SeasonLeaderboardDto>> seasonLeaderboard(String seasonId) {
    return _transport.getObject<SeasonLeaderboardDto>(
      '/seasons/$seasonId/leaderboard',
      parse: SeasonLeaderboardDto.fromJson,
    );
  }

  /// `GET /rounds/{id}/leaderboard` — a round's ranked standings.
  ///
  /// Returns:
  ///   * `Ok(RoundLeaderboardDto)` on `200` — an **empty** `entries` list is a
  ///     legitimate result (a scored round nobody predicted), never an error;
  ///   * `Err(invariant, code: scoring.round_not_scored)` on `409` when the
  ///     round has not been scored yet;
  ///   * `Err(authorization, code: scoring.not_a_participant)` on `401` when
  ///     the caller is not a member of the round's season;
  ///   * `Err(validation)` if [roundId] is malformed (server `400`);
  ///   * `Err(transient)` on `503` or a network failure (retryable);
  ///   * `Err(validation, code: api_client.malformed_response)` if the `200`
  ///     body is not a valid [RoundLeaderboardDto].
  Future<Result<RoundLeaderboardDto>> roundLeaderboard(String roundId) {
    return _transport.getObject<RoundLeaderboardDto>(
      '/rounds/$roundId/leaderboard',
      parse: RoundLeaderboardDto.fromJson,
    );
  }

  /// `GET /leaderboard/hall-of-fame` — the platform-wide, all-time standings.
  /// [limit] is an optional page-size hint; the server clamps an untrusted
  /// value rather than rejecting it. An **empty** `entries` list is a
  /// legitimate result (nobody has ever been credited yet), never an error.
  Future<Result<HallOfFameDto>> hallOfFame({int? limit}) {
    return _transport.getObject<HallOfFameDto>(
      '/leaderboard/hall-of-fame',
      query: limit == null ? null : {'limit': '$limit'},
      parse: HallOfFameDto.fromJson,
    );
  }
}
