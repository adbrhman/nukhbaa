import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /me/badges` -- the badge catalog with the caller's progress and the
/// moment each held badge was granted (P2-8).
///
/// Read from `gamification.events` on every request; nothing is stored for
/// it, and no client-supplied number is ever trusted (Axioms 2/5 -- the
/// server owns every count). Badges are granted by the evaluator on its own
/// schedule, never by this read.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getMyBadges(principal: principal);

  return switch (result) {
    Ok<List<MyBadge>>(:final value) => Response.json(
      body: MyBadgesDto(
        badges: [
          for (final badge in value)
            BadgeDto(
              code: badge.code.wireName,
              current: badge.current,
              target: badge.target,
              unlockedAt: badge.unlockedAt?.toUtc().toIso8601String(),
            ),
        ],
      ).toJson(),
    ),
    Err<List<MyBadge>>(:final error) => errorResponse(error),
  };
}
