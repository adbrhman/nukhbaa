import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /feed/matches` — the unified matches feed: every currently-open
/// round's fixture(s) across every public competition, flattened into one
/// ordered list (query intent `ListMatchesFeed`; server-side aggregate read
/// replacing the client-side competition -> season -> round -> fixtures
/// drill-down). Read-only, no side effect. Authenticated (bearerAuth via
/// `feed/_middleware.dart`).
///
/// No open rounds anywhere — or none with any linked fixture — is a
/// legitimate empty JSON array (no existence oracle). Any method other than
/// `GET` is `405`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listMatchesFeed(principal: principal);

  return switch (result) {
    Ok<List<MatchFeedEntry>>(:final value) => Response.json(
      body: [for (final entry in value) matchFeedEntryToDto(entry).toJson()],
    ),
    Err<List<MatchFeedEntry>>(:final error) => errorResponse(error),
  };
}
