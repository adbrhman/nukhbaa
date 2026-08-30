// ignore_for_file: file_names
//
// The hyphen is required, not a style slip: dart_frog derives the route
// path from this file's name verbatim, and `GET /me/active-seasons` is only
// produced by this exact file name (mirrors `routes/me/fixture-predictions.dart`).

import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// GET /me/active-seasons — every season the caller is an **active**
/// participant in, right now (docs/project-context.md, Axiom 4 Amendment;
/// the participant-scoped "my seasons" read the client fans out from, one
/// call per season, to the existing `GET /seasons/{id}/fixtures`).
///
/// **Visibility:** always the caller's own participation — there is no
/// season-membership check to perform at this route: `ListMyActiveSeasons`
/// already scopes the read to `AuthenticatedUser.userId`, so nothing here
/// can reveal another user's participation. This route only wires the
/// verified principal and shapes the result; it makes no authorization
/// decision of its own.
///
/// The `/me` subtree is already behind `bearerAuth`
/// (`routes/me/_middleware.dart`), which provides the [AuthenticatedUser]; an
/// unauthenticated request never reaches this handler. Returns a JSON array
/// of [ActiveSeasonDto], ordered per `CompetitionRepository.
/// listActiveParticipantSeasons` (competition name, then season label);
/// an empty array means the caller has no active participation right now — a
/// legitimate result (e.g. a brand-new user who has not yet made a first
/// prediction), never an error. `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listMyActiveSeasons(principal: principal);

  return switch (result) {
    Ok<List<ParticipantSeasonFeedEntry>>(:final value) => Response.json(
      body: [for (final entry in value) activeSeasonToDto(entry).toJson()],
    ),
    Err<List<ParticipantSeasonFeedEntry>>(:final error) => errorResponse(error),
  };
}
