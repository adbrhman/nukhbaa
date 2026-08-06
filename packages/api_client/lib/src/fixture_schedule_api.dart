import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the fixture-IDENTITY seam of `apps/server` (Axiom 3;
/// Next-Task decision 2026-07-11, option (a)): which two sides play and when,
/// decoupled from any competition/round reference.
///
/// Wraps the ratified routes verbatim — no invented path:
///   * `POST /fixtures` -> [FixtureScheduleDto] (`routes/fixtures/index.dart`),
///     registration; the fixture id is server-generated.
///   * `PUT  /fixtures/{id}` -> [FixtureScheduleDto]
///     (`routes/fixtures/[id]/index.dart`), correction; the fixture id
///     travels in the path.
///
/// Both share the single request shape [FixtureScheduleRequestDto] (see its
/// own doc comment) — the id/action distinction lives in the route, never in
/// a second DTO.
///
/// **Admin-only**, enforced entirely inside the server use-cases
/// (`RegisterFixtureSchedule` / `CorrectFixtureSchedule`) — this client makes
/// no authorization decision of its own; a non-admin caller is refused `401`
/// with no client-side oracle. The whole `/fixtures` subtree is already
/// behind `bearerAuth` (`routes/fixtures/_middleware.dart`); an
/// unauthenticated call is refused there with `401`.
///
/// Every method returns a typed [Result] and never throws.
final class FixtureScheduleApi {
  /// Creates the fixture-schedule client over the shared [ApiTransport].
  const FixtureScheduleApi(this._transport);

  final ApiTransport _transport;

  /// `POST /fixtures` — registers a new fixture's identity. The server
  /// generates [FixtureScheduleDto.fixtureId]; the caller supplies only the
  /// two team names and the kickoff time.
  Future<Result<FixtureScheduleDto>> registerFixtureSchedule({
    required String homeTeam,
    required String awayTeam,
    required String kickoffAt,
  }) {
    return _transport.postObject<FixtureScheduleDto>(
      '/fixtures',
      body: FixtureScheduleRequestDto(
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        kickoffAt: kickoffAt,
      ).toJson(),
      parse: FixtureScheduleDto.fromJson,
    );
  }

  /// `PUT /fixtures/{fixtureId}` — corrects an already-registered fixture's
  /// identity (or registers it under this id, if unknown — an idempotent
  /// upsert, matching `fixture_result` recording's contract). Used by an
  /// admin to fix a mistyped team name or kickoff time before the round is
  /// linked/locked.
  Future<Result<FixtureScheduleDto>> correctFixtureSchedule({
    required String fixtureId,
    required String homeTeam,
    required String awayTeam,
    required String kickoffAt,
  }) {
    return _transport.putObject<FixtureScheduleDto>(
      '/fixtures/$fixtureId',
      body: FixtureScheduleRequestDto(
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        kickoffAt: kickoffAt,
      ).toJson(),
      parse: FixtureScheduleDto.fromJson,
    );
  }
}
