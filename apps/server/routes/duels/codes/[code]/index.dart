import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/duel_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /duels/codes/{code}` -- open a shared duel link (migration 0090).
///
/// Answers `200` with the challenge as the caller sees it: the fixture, the
/// challenger's name, the seats taken and the derived state. Never any
/// prediction. An unknown code is `409 social.duel_challenge_not_found`, a
/// malformed one `400 social.duel_code_malformed`.
Future<Response> onRequest(RequestContext context, String code) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.getDuelChallengeByCode(
    principal: principal,
    code: code,
  );

  return switch (result) {
    Ok<DuelChallengeView>(:final value) => Response.json(
      body: duelChallengeViewToDto(value).toJson(),
    ),
    Err<DuelChallengeView>(:final error) => errorResponse(error),
  };
}
