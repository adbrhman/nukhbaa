import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_cup_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /me/h2h-cup` -- the caller's Elite Cup of the head-to-head league
/// (NK185, migration 0190): whether he qualified, the path he plays (the
/// first, second or third places of the four elite groups), the qualifiers
/// of that path, and its two stages with their day, pairs, results and
/// title.
///
/// A caller outside every open cup reads `state: spectator` with the path of
/// the first places (the group leaders) to watch, or `state: not_qualified`
/// and nothing else when no cup is open. Names, days and the figures that decided a pair only: no
/// prediction of anybody arrives here. Nothing is computed on the client
/// (Axioms 2/5).
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getMyH2hCup(principal: principal);

  return switch (result) {
    Ok<MyH2hCup>(:final value) => Response.json(
      body: myH2hCupToDto(value).toJson(),
    ),
    Err<MyH2hCup>(:final error) => errorResponse(error),
  };
}
