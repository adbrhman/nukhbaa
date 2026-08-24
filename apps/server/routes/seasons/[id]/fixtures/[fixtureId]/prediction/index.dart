import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_prediction_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /seasons/{id}/fixtures/{fixtureId}/prediction` — submit (or
/// idempotently amend) the caller's prediction for a single fixture (API ADR
/// §2: command intent `SubmitFixturePrediction`; docs/project-context.md,
/// Axiom 4 Amendment — the per-fixture sibling of `POST
/// /rounds/{id}/predictions`, so one fixture — or more, one call each — can be
/// predicted and later scored without waiting on a round to close).
///
/// The body is a [FixturePredictionCommandDto] (predicted scoreline + the
/// optional `is_double` flag only); the participant is resolved server-side
/// from the verified principal and the season named in the path, **never**
/// from the body (Security ADR §2 / Axiom 2). Points are never accepted or
/// returned. Returns the stored [FixturePredictionDto] (`200`) — one row per
/// `(fixture, participant)` (Axiom 4 Amendment), so both a first submission
/// and an amendment resolve to the same resource.
///
/// The whole `/seasons` subtree is already behind `bearerAuth`
/// (`routes/seasons/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String fixtureId,
) async {
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

  final homeResult = requireInt(body, 'home_goals');
  if (homeResult is Err<int>) {
    return errorResponse(homeResult.error);
  }
  final awayResult = requireInt(body, 'away_goals');
  if (awayResult is Err<int>) {
    return errorResponse(awayResult.error);
  }
  final isDoubleResult = _optionalBool(body, 'is_double');
  if (isDoubleResult is Err<bool>) {
    return errorResponse(isDoubleResult.error);
  }

  final result = await root.submitFixturePrediction(
    principal: principal,
    seasonId: id,
    fixtureId: fixtureId,
    homeGoals: (homeResult as Ok<int>).value,
    awayGoals: (awayResult as Ok<int>).value,
    isDouble: (isDoubleResult as Ok<bool>).value,
  );

  return switch (result) {
    Ok<FixturePredictionView>(:final value) => Response.json(
      body: fixturePredictionViewToJson(value),
    ),
    Err<FixturePredictionView>(:final error) => errorResponse(error),
  };
}

/// Extracts an optional boolean field, defaulting to `false` when absent —
/// mirrors the inline `is_double` parsing in
/// `routes/rounds/[id]/predictions/index.dart`'s `_parseScores`. A present but
/// wrongly-typed value is still a transport-validation failure (400).
Result<bool> _optionalBool(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value == null) {
    return const Result.ok(false);
  }
  if (value is bool) {
    return Result.ok(value);
  }
  return Result.err(
    AppError.validation(
      'request.field_missing',
      'Field "$field", when present, must be a boolean',
    ),
  );
}
