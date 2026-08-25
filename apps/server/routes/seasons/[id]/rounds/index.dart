import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `/seasons/{id}/rounds` collection endpoint.
///
/// * `GET` — list the season's rounds, ordered by 1-based sequence (API ADR §2:
///   query intent `ListSeasonRounds`; added under the FA-1 season/round browse
///   scope closure — read-only, no side effect). A season with no rounds, or one
///   that does not exist, yields a legitimate empty JSON array (no existence
///   oracle — the use-case never 404s a round list). Returns a JSON array of
///   [RoundDto] (ruleset *version* only — the opaque frozen snapshot is never
///   exposed).
///
/// Authenticated (bearerAuth middleware; the `/seasons` subtree already
/// applies it via `seasons/_middleware.dart`). Any other method is `405`.
Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _list(context, id),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

/// GET /seasons/{id}/rounds — the read-only round browse (FA-1 closure).
Future<Response> _list(RequestContext context, String id) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listSeasonRounds(
    principal: principal,
    seasonId: id,
  );

  return switch (result) {
    // `value` is already every round in the season (sequence-ordered), so it
    // doubles as the `seasonRounds` sibling context each entry needs for
    // `isPredictable` — no extra read.
    Ok<List<Round>>(:final value) => Response.json(
      body: [
        for (final round in value)
          roundToDto(round, seasonRounds: value).toJson(),
      ],
    ),
    Err<List<Round>>(:final error) => errorResponse(error),
  };
}

