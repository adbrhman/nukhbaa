// NK312_02
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_cup_board_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /me/h2h-cup/board` -- the Elite Cup of the month for any signed-in
/// player or admin (script 312): the three paths, their stages, pairs and
/// fixtures, with both players' picks on each fixture.
///
/// **A pick of another player is on this wire only once its fixture has
/// kicked off.** A side whose pick is withheld is written as
/// `{"revealed": false}`: no pick, and no sign of whether the player
/// predicted. The caller's own picks are always shown. An admin who is not
/// an owner reads exactly what a player reads; the owners read the whole
/// board only through `/owner/h2h-cup/picks`.
///
/// No cup: `200` with no `month_start` and no paths. `405` on any method
/// but GET. Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getH2hCupBoard(principal: principal);

  return switch (result) {
    Ok<H2hCupBoard>(:final value) => Response.json(
      body: h2hCupBoardToDto(value).toJson(),
    ),
    Err<H2hCupBoard>(:final error) => errorResponse(error),
  };
}
