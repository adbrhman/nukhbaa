import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /me/streak` -- how many match days in a row the caller has completed.
///
/// Counted from `gamification.events` on every request; there is no stored
/// streak to go stale, and no client-supplied number is ever trusted
/// (Axioms 2/5 — the server owns every count).
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getMyStreak(principal: principal);

  return switch (result) {
    Ok<StreakTally>(:final value) => Response.json(
      body: MyStreakDto(
        current: value.current,
        longest: value.longest,
      ).toJson(),
    ),
    Err<StreakTally>(:final error) => errorResponse(error),
  };
}
