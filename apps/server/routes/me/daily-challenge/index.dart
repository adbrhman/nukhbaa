import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /me/daily-challenge` -- how much of today's match day the caller has
/// covered (P1-6).
///
/// Computed on every request from the caller's active seasons and today's
/// fixtures; nothing is stored, so there is no cached number to go stale, and
/// no client-supplied count is ever trusted (Axioms 2/5 -- the server owns
/// every count).
///
/// `day` is the Riyadh day, the same boundary the streak uses. A day with no
/// fixtures answers `total: 0, complete: false` -- a legitimate rest day, not
/// an error.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getMyDailyChallenge(principal: principal);

  return switch (result) {
    Ok<MyDailyChallenge>(:final value) => Response.json(
      body: MyDailyChallengeDto(
        day: _isoDay(value.day),
        total: value.total,
        predicted: value.predicted,
        complete: value.isComplete,
      ).toJson(),
    ),
    Err<MyDailyChallenge>(:final error) => errorResponse(error),
  };
}

/// Formats a UTC-midnight day as `YYYY-MM-DD`, matching the shape
/// `GamificationEvent` writes into a dedupe key.
String _isoDay(DateTime day) {
  final utc = day.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}
