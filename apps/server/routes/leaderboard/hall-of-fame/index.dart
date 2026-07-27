import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/leaderboard_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /leaderboard/hall-of-fame — read the platform-wide, all-time standings
/// (API ADR §2: a query; the Hall of Fame is a read-side projection over the
/// SAME append-only ledger the season board reads — Axiom 5, never a points
/// write, so there is no command here).
///
/// **Deliberately public, unlike the season board:** the visibility gate
/// inside `GetHallOfFame` requires only an authenticated `PlatformRole.user`
/// — no season-membership check. This route only wires the verified principal
/// and an optional `limit` query parameter and shapes the result; it makes no
/// authorization decision of its own.
///
/// The `/leaderboard` subtree is already behind `bearerAuth`
/// (`routes/leaderboard/_middleware.dart`), which provides the
/// [AuthenticatedUser]; an unauthenticated request never reaches this
/// handler. An untrusted `limit` is clamped by the use-case rather than
/// rejected, so a malformed or oversized value can never trigger an
/// unbounded scan — it degrades to the default/max page size instead of a
/// `400`. Returns the [HallOfFameDto] (`200`); an empty `entries` array means
/// nobody has ever been credited yet (a legitimate empty board). `405` on any
/// non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final rawLimit = context.request.uri.queryParameters['limit'];
  final limit = rawLimit == null ? null : int.tryParse(rawLimit);

  final result = await root.getHallOfFame(principal: principal, limit: limit);

  return switch (result) {
    Ok<HallOfFame>(:final value) => Response.json(
      body: hallOfFameToJson(value),
    ),
    Err<HallOfFame>(:final error) => errorResponse(error),
  };
}
