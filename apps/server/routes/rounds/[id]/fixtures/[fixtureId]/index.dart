import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `/rounds/{id}/fixtures/{fixtureId}` — a single round↔fixture link.
///
/// * `DELETE` — remove the fixture from the round (command intent
///   `RemoveFixtureFromRound`; the correction counterpart of `POST
///   /rounds/{id}/fixtures` for a duplicate/mistaken link). Admin-only
///   (use-case layer). Rejected as an error envelope when the round is no
///   longer open, or when the fixture already carries a recorded result
///   (`competition.fixture_result_already_recorded`) — a scored fixture is
///   never silently dropped. Idempotent: removing an already-absent link is
///   a success (`removed: false`), never a `404`.
/// * anything else → `405`.
///
/// Authenticated via the `/rounds` subtree's `bearerAuth` middleware
/// (`rounds/_middleware.dart`).
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

  final result = await root.removeFixtureFromRound(
    principal: principal,
    roundId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    // The boolean is echoed so a client can tell an actual removal (true)
    // from a no-op (false); both are `200` (idempotent, mirrors the
    // reactions `DELETE` endpoint).
    Ok<bool>(:final value) => Response.json(body: {'removed': value}),
    Err<bool>(:final error) => errorResponse(error),
  };
}
