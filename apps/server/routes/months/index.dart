import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// GET /months -- the monthly contest seasons, newest first (query intent
/// `ListMonthlySeasons`).
///
/// The contest is the calendar month, and this is the only read that says
/// which months exist: `GET /competitions/{id}/seasons` answers one
/// competition at a time and would require the caller to already know
/// which competition owns the months.
///
/// Read-only, no side effect. Returns a JSON array of [SeasonDto], the
/// same envelope convention as `GET /competitions/{id}/seasons`. No months
/// yet is a legitimate empty array, never an error.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listMonthlySeasons(principal: principal);

  return switch (result) {
    Ok<List<CompetitionSeason>>(:final value) => Response.json(
      body: [for (final s in value) seasonToDto(s).toJson()],
    ),
    Err<List<CompetitionSeason>>(:final error) => errorResponse(error),
  };
}
