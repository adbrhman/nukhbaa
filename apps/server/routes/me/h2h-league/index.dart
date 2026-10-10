import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /me/h2h-league` -- the caller's head-to-head month (migration 0100):
/// their group's table over the settled rounds, every approved round with
/// its phase (`open` is the next one), its first kickoff and the result it
/// shows (points only while live), the days left, and for each round
/// the caller's opponent and match, and the zones.
///
/// Before the league opens (`starts_on`), and for anybody outside the pilot,
/// `state` is `not_started`; a drawn month without the caller is
/// `not_in_draw`. Nothing is computed on the client (Axioms 2/5).
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getMyH2hMonth(principal: principal);

  return switch (result) {
    Ok<MyH2hMonth>(:final value) => Response.json(
      body: myH2hMonthToDto(value).toJson(),
    ),
    Err<MyH2hMonth>(:final error) => errorResponse(error),
  };
}
