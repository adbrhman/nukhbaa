import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/duel_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /duels/challenges/{id}/accept` -- accept a duel challenge with the
/// caller's own prediction (migration 0090).
///
/// Body: `{"home_goals": 2, "away_goals": 1, "is_double": false}`. The
/// prediction is saved through the ordinary prediction path first; the
/// database then locks the challenge and creates the duel only if both
/// predictions exist. A refused acceptance leaves the saved prediction as
/// it is. Answers `200` with the duel.
///
/// A player who has not opened the app since the month began is not in the
/// season yet; like `POST /seasons/{id}/fixtures/{fixtureId}/prediction`,
/// the first `prediction.not_a_participant` joins them and tries once more.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final home = requireInt(body, 'home_goals');
  if (home is Err<int>) {
    return errorResponse(home.error);
  }
  final away = requireInt(body, 'away_goals');
  if (away is Err<int>) {
    return errorResponse(away.error);
  }
  final rawDouble = body['is_double'];
  if (rawDouble != null && rawDouble is! bool) {
    return errorResponse(
      const AppError.validation(
        'request.field_missing',
        'Field "is_double" must be a boolean',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  Future<Result<Duel>> accept() => root.acceptDuelChallenge(
    principal: principal,
    challengeId: id,
    homeGoals: (home as Ok<int>).value,
    awayGoals: (away as Ok<int>).value,
    isDouble: rawDouble == true,
  );

  var result = await accept();
  if (result case Err<Duel>(
    :final error,
  ) when error.code == 'prediction.not_a_participant') {
    await root.enrolInOpenSeasons(
      principal: principal,
      now: DateTime.now().toUtc(),
    );
    result = await accept();
  }

  return switch (result) {
    Ok<Duel>(:final value) => Response.json(body: duelToDto(value).toJson()),
    Err<Duel>(:final error) => errorResponse(error),
  };
}
