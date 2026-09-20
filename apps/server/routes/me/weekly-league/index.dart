import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/weekly_league_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /me/weekly-league` -- the caller's own weekly-league group, ranked
/// (P2-4).
///
/// The read seats the caller if this is the first time the week has seen
/// them (a player who installs on Wednesday plays on Wednesday), then ranks
/// the group from the one source of points the monthly board uses. Nothing
/// weekly is stored, so there is no cached standing to go stale, and no
/// client-supplied number is ever trusted (Axioms 2/5 -- the server owns
/// every count).
///
/// The week is Monday through Sunday, Riyadh. A tier is the number 1..5; the
/// names are the client's.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getMyWeeklyLeague(principal: principal);

  return switch (result) {
    Ok<MyWeeklyLeague>(:final value) => Response.json(
      body: myWeeklyLeagueToDto(value).toJson(),
    ),
    Err<MyWeeklyLeague>(:final error) => errorResponse(error),
  };
}
