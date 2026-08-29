import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /feed/current-month-fixtures` -- the current-month fixture feed:
/// every public competition's current (calendar-month) season, fixtures
/// flattened into one ordered list (query intent
/// `ListCurrentMonthFixtures`; Monthly Competitions transition,
/// project-context.md section 9). Read-only, no side effect. Authenticated
/// (bearerAuth via `feed/_middleware.dart`).
///
/// No public competitions, none with a season currently covering "now", or
/// none of those seasons having a linked fixture are all legitimate empty
/// JSON arrays (no existence oracle). Any method other than `GET` is `405`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listCurrentMonthFixtures(principal: principal);

  return switch (result) {
    Ok<List<CurrentMonthFixtureEntry>>(:final value) => Response.json(
      body: [
        for (final entry in value)
          currentMonthFixtureEntryToDto(entry).toJson(),
      ],
    ),
    Err<List<CurrentMonthFixtureEntry>>(:final error) => errorResponse(error),
  };
}
