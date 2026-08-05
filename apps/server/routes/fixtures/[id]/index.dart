import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// PUT /fixtures/{id} — correct an already-registered fixture's identity
/// (API ADR §2: command intent `CorrectFixtureSchedule`). Admin-only,
/// enforced inside the use-case (Axioms 2/5).
///
/// This is the correction side of the Axiom-3 schedule seam (Next-Task
/// decision 2026-07-11, option (a)), the sibling of `POST /fixtures`
/// (registration): the fixture id travels in the path (an admin correcting a
/// mistyped team name or kickoff time before the round is linked/locked),
/// never generated here. `PUT` (not `PATCH`) because the operation is a full
/// idempotent upsert on the fixture id, matching the same convention as `PUT
/// /fixtures/{id}/result`.
///
/// Body: `{ "home_team": string, "away_team": string, "kickoff_at": ISO-8601
/// string }` ([FixtureScheduleRequestDto] — the same shape `POST /fixtures`
/// accepts). Returns the stored [FixtureScheduleDto] (`200`).
///
/// The `/fixtures` subtree is already behind `bearerAuth`
/// (`routes/fixtures/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object>>).value;

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

  final result = await root.correctFixtureSchedule(
    principal: principal,
    fixtureId: id,
    homeTeam: (homeResult as Ok<String>).value,
    awayTeam: (awayResult as Ok<String>).value,
    kickoffAt: (kickoffResult as Ok<DateTime>).value,
  );

  return switch (result) {
    Ok<FixtureSchedule>(:final value) => Response.json(
      body: FixtureScheduleDto(
        fixtureId: value.fixture.value,
        homeTeam: value.homeTeam,
        awayTeam: value.awayTeam,
        kickoffAt: value.kickoffAt.toIso8601String(),
      ).toJson(),
    ),
    Err<FixtureSchedule>(:final error) => errorResponse(error),
  };
}

/// Parses the untrusted `kickoff_at` field into a UTC [DateTime]. Mirrors
/// `_parseKickoff` in `routes/fixtures/index.dart` (register) and
/// `_parseDeadline` in `routes/seasons/[id]/rounds/index.dart`.
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
