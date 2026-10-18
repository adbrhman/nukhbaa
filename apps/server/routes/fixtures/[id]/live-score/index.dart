import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `PUT /fixtures/{id}/live-score` -- an admin corrects the running score of
/// a match in play that the provider has wrong (a goal ruled out by VAR the
/// feed still counts; Paris FC - Rennes, 2026-10-18). Body:
/// `{ "home_goals": int, "away_goals": int }`. The match card and the live
/// points change at once, and the result sync records the corrected score
/// at full time (`AdminCorrectLiveScore`). Answers
/// `{ "fixture_id", "home_goals", "away_goals" }`; `409
/// football_data.not_live` while the provider reports no running score.
///
/// `DELETE /fixtures/{id}/live-score` -- takes the correction back; the
/// provider's figure shows and counts again. Answers `{ "cleared": true }`.
///
/// Admin-only, enforced inside the use-case; the `/fixtures` subtree is
/// behind `bearerAuth`. Any other method is `405`.
Future<Response> onRequest(RequestContext context, String id) async {
  final method = context.request.method;
  if (method != HttpMethod.put && method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final correct = root.correctLiveScore;
  if (correct == null) {
    return Response(statusCode: HttpStatus.notFound);
  }

  if (method == HttpMethod.delete) {
    return switch (correct.clear(principal: principal, fixtureId: id)) {
      Ok<void>() => Response.json(body: {'cleared': true}),
      Err<void>(:final error) => errorResponse(error),
    };
  }

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

  final result = correct(
    principal: principal,
    fixtureId: id,
    homeGoals: (homeResult as Ok<int>).value,
    awayGoals: (awayResult as Ok<int>).value,
  );
  return switch (result) {
    Ok<LiveScoreCorrection>(:final value) => Response.json(
      body: {
        'fixture_id': id,
        'home_goals': value.homeGoals,
        'away_goals': value.awayGoals,
      },
    ),
    Err<LiveScoreCorrection>(:final error) => errorResponse(error),
  };
}
