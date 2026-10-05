import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/duel_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/rate_limit.dart';
import 'package:shared/shared.dart';

/// `POST /duels/challenges` -- create a duel challenge on one fixture
/// (migration 0090).
///
/// Body: `{"season_id": "...", "fixture_id": "...", "capacity": 5,
/// "target_user_id": "..."}`; `capacity` and `target_user_id` are optional
/// (a private challenge has capacity one). The caller must already have a
/// prediction for the fixture and kickoff must be at least 30 minutes away.
///
/// Answers `201` with the challenge as the caller sees it, read back by its
/// code so the body carries the fixture and the share code. Every refusal is
/// the use-case's or the database's, in the uniform error envelope.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final principal = context.read<AuthenticatedUser>();
  final limited = limitPlayerAppend(PlayerAppend.duelChallenge, principal);
  if (limited != null) {
    return limited;
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final seasonId = requireString(body, 'season_id');
  if (seasonId is Err<String>) {
    return errorResponse(seasonId.error);
  }
  final fixtureId = requireString(body, 'fixture_id');
  if (fixtureId is Err<String>) {
    return errorResponse(fixtureId.error);
  }
  final rawCapacity = body['capacity'];
  if (rawCapacity != null && rawCapacity is! int) {
    return errorResponse(
      const AppError.validation(
        'request.field_missing',
        'Field "capacity" must be an integer',
      ),
    );
  }
  final rawTarget = body['target_user_id'];
  if (rawTarget != null && rawTarget is! String) {
    return errorResponse(
      const AppError.validation(
        'request.field_missing',
        'Field "target_user_id" must be a string',
      ),
    );
  }
  final target = rawTarget as String?;
  final capacity =
      (rawCapacity as int?) ??
      (target == null ? DuelPolicy.defaultCapacity : 1);

  final root = await context.read<Future<CompositionRoot>>();
  final created = await root.createDuelChallenge(
    principal: principal,
    seasonId: (seasonId as Ok<String>).value,
    fixtureId: (fixtureId as Ok<String>).value,
    capacity: capacity,
    targetUserId: target,
  );
  if (created is Err<DuelChallenge>) {
    return errorResponse(created.error);
  }

  final view = await root.getDuelChallengeByCode(
    principal: principal,
    code: (created as Ok<DuelChallenge>).value.code.value,
  );
  return switch (view) {
    Ok<DuelChallengeView>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: duelChallengeViewToDto(value).toJson(),
    ),
    Err<DuelChallengeView>(:final error) => errorResponse(error),
  };
}
