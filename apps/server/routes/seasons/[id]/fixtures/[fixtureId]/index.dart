import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `/seasons/{id}/fixtures/{fixtureId}` — the single season-fixture link.
///
/// * `DELETE` — unlink the fixture from the season (command intent
///   `RemoveFixtureFromSeason`; the season-scoped sibling of
///   `DELETE /rounds/{id}/fixtures/{fixtureId}`). Admin-only and guarded
///   inside the use-case, which refuses once the fixture carries any
///   prediction or a recorded result. Idempotent: `{"removed": false}` when
///   there was no link, which is a success, not a `404` — the same shape the
///   reaction removal already returns.
/// * anything else → `405`.
///
/// Authenticated via the `/seasons` `bearerAuth` subtree
/// (`seasons/_middleware.dart`); this route makes no authorization decision
/// of its own.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.removeFixtureFromSeason(
    principal: principal,
    seasonId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<bool>(:final value) => Response.json(body: {'removed': value}),
    Err<bool>(:final error) => errorResponse(error),
  };
}
