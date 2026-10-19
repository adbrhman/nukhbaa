import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /fixtures/{id}/details` -- the story of a finished match for its
/// details page (script 118): the events with their minutes, the half-time
/// score, the ground, as `SyncMatchDetails` read them from Highlightly once
/// the result was recorded. `available: false` while they have not been
/// read, or when the provider has no such match. Any signed-in user
/// (`GetMatchDetails`; the `/fixtures` subtree is behind `bearerAuth`).
/// Any other method is `405`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final read = root.getMatchDetails;
  if (read == null) {
    return Response.json(
      body: MatchDetailsDto(fixtureId: id, available: false).toJson(),
    );
  }

  final result = await read(principal: principal, fixtureId: id);
  return switch (result) {
    Ok<MatchDetails?>(:final value) => Response.json(
      body: matchDetailsToDto(id, value).toJson(),
    ),
    Err<MatchDetails?>(:final error) => errorResponse(error),
  };
}

/// The wire shape of [details] for the fixture [id]; nothing to show when
/// none were read or the provider had no such match.
MatchDetailsDto matchDetailsToDto(String id, MatchDetails? details) {
  if (details == null || !details.found) {
    return MatchDetailsDto(fixtureId: id, available: false);
  }
  return MatchDetailsDto(
    fixtureId: id,
    available: true,
    events: <MatchEventDto>[
      for (final MatchEvent event in details.events)
        MatchEventDto(
          minute: event.minute,
          kind: event.kind.wire,
          home: event.home,
          player: event.player,
          assist: event.assist,
        ),
    ],
    halfTimeHome: details.halfTimeHome,
    halfTimeAway: details.halfTimeAway,
    venue: details.venue,
    round: details.round,
    referee: details.referee,
  );
}
