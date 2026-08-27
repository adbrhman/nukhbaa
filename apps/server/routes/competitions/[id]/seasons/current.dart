import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /competitions/{id}/seasons/current` — resolves the single "current"
/// monthly season of a competition (7.7 step 4).
///
/// Strictly a read: current-ness is computed fresh from `start_at`/`end_at`
/// against "now" (`GetCurrentSeason`), never stored. A month with no season
/// yet created by the admin is a legitimate `200` with a JSON `null` body —
/// the same "no existence oracle" philosophy as
/// `GET /competitions/{id}/seasons` (which returns `[]`, never `404`) — not
/// the "owned resource" philosophy of `GetMyPrediction` (which `404`s).
///
/// Any method other than `GET` is `405`.
Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _current(context, id),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

Future<Response> _current(RequestContext context, String id) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getCurrentSeason(
    principal: principal,
    competitionId: id,
  );

  return switch (result) {
    Ok<CompetitionSeason?>(:final value) => value == null
        ? Response(
            statusCode: HttpStatus.ok,
            body: 'null',
            headers: const {'content-type': 'application/json'},
          )
        : Response.json(body: seasonToDto(value).toJson()),
    Err<CompetitionSeason?>(:final error) => errorResponse(error),
  };
}
