import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// POST /fixtures — register a new fixture's identity: home/away team names
/// and kickoff time (API ADR §2: command intent `RegisterFixtureSchedule`).
/// Admin-only, enforced inside the use-case (Axioms 2/5).
///
/// This is the registration side of the Axiom-3 schedule seam (Next-Task
/// decision 2026-07-11, option (a), applied to schedule rather than outcome):
/// with no Football-Data phase yet, an admin feeds a fixture's identity
/// through this minimal command rather than an automated feed. The fixture id
/// is server-generated (`POST`, not `PUT`) — the caller never supplies one, so
/// a retried call would create a second fixture rather than converge; a client
/// that must correct an already-registered fixture uses `PUT /fixtures/{id}`
/// instead. It carries no competition/round reference (Axiom 3): the same
/// fixture may later be linked into many rounds via `LinkFixtureToRound`.
///
/// Body: `{ "home_team": string, "away_team": string, "kickoff_at": ISO-8601
/// string }` ([FixtureScheduleRequestDto]). Returns the stored
/// [FixtureScheduleDto] (`201`); an invalid team name (empty, over 120 chars,
/// or identical to the other side) surfaces as `400` via the shared error
/// envelope.
///
/// The `/fixtures` subtree is already behind `bearerAuth`
/// (`routes/fixtures/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final homeResult = requireString(body, 'home_team');
  if (homeResult is Err<String>) {
    return errorResponse(homeResult.error);
  }
  final awayResult = requireString(body, 'away_team');
  if (awayResult is Err<String>) {
    return errorResponse(awayResult.error);
  }
  final kickoffResult = _parseKickoff(body['kickoff_at']);
  if (kickoffResult is Err<DateTime>) {
    return errorResponse(kickoffResult.error);
  }

  final result = await root.registerFixtureSchedule(
    principal: principal,
    homeTeam: (homeResult as Ok<String>).value,
    awayTeam: (awayResult as Ok<String>).value,
    kickoffAt: (kickoffResult as Ok<DateTime>).value,
    homeTeamId: body['home_team_id'] as String?,
    awayTeamId: body['away_team_id'] as String?,
  );

  return switch (result) {
    Ok<FixtureSchedule>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: FixtureScheduleDto(
        fixtureId: value.fixture.value,
        homeTeam: value.homeTeam,
        awayTeam: value.awayTeam,
        kickoffAt: value.kickoffAt.toIso8601String(),
        homeTeamId: value.homeTeamId?.value,
        awayTeamId: value.awayTeamId?.value,
      ).toJson(),
    ),
    Err<FixtureSchedule>(:final error) => errorResponse(error),
  };
}

/// Parses the untrusted `kickoff_at` field into a UTC [DateTime]. Mirrors
/// `_parseDeadline` in `routes/seasons/[id]/rounds/index.dart`: requires an
/// ISO-8601 string, normalized to UTC so the domain receives a consistent
/// instant regardless of the offset the caller supplied.
Result<DateTime> _parseKickoff(Object? raw) {
  if (raw is! String) {
    return const Result.err(
      AppError.validation(
        'request.field_missing',
        'Field "kickoff_at" is required and must be an ISO-8601 string',
      ),
    );
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return const Result.err(
      AppError.validation(
        'request.kickoff_malformed',
        'Field "kickoff_at" must be a valid ISO-8601 instant',
      ),
    );
  }
  return Result.ok(parsed.toUtc());
}
