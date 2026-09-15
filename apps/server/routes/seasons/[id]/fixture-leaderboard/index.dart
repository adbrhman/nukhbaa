import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/leaderboard_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /seasons/{id}/fixture-leaderboard — read a season's live, "monthly"
/// fixture leaderboard (Axiom 4 Amendment; the per-fixture, always-current
/// sibling of `GET /rounds/{id}/leaderboard` — a read-side projection over
/// the season's already-computed fixture scores, never a points write).
///
/// Unlike the round leaderboard, there is no "must be fully scored" gate:
/// the board reflects whatever fixtures have been scored so far (Axiom 4
/// Amendment — scoring is live, per-fixture, never waiting on the rest of
/// the season). The only gate is season membership, enforced entirely inside
/// `GetSeasonFixtureLeaderboard`: a non-member is rejected `401`
/// `leaderboard.not_a_participant`.
///
/// This is a brand-new, additive route — it does not replace or modify
/// `GET /rounds/{id}/leaderboard` or any existing round-scoped endpoint.
/// Optional `from` (inclusive) / `to` (exclusive) ISO-8601 query parameters
/// narrow the board to fixtures kicking off inside that window -- the
/// mobile client sends the UTC boundaries of the device-local day. Both must
/// be present together.
///
/// `405` on any non-GET method.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final query = context.request.uri.queryParameters;
  final from = _parseUtc(query['from']);
  final to = _parseUtc(query['to']);
  if ((query['from'] != null && from == null) ||
      (query['to'] != null && to == null)) {
    return errorResponse(
      const AppError.validation(
        'leaderboard.invalid_window',
        'Invalid date window',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getSeasonFixtureLeaderboard(
    principal: principal,
    seasonId: id,
    fromUtc: from,
    toUtc: to,
  );

  return switch (result) {
    Ok<FixtureLeaderboard>(:final value) => Response.json(
      body: fixtureLeaderboardToJson(value),
    ),
    Err<FixtureLeaderboard>(:final error) => errorResponse(error),
  };
}

DateTime? _parseUtc(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
