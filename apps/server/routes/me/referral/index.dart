import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /me/referral` -- the caller's fixed invitation code and counters
/// (migration 0073). `?install=` is the app's install id: remembered hashed
/// so a friend on the inviter's own install is held for review.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`. `405` on any
/// non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getMyReferral(
    principal: principal,
    installId: context.request.uri.queryParameters['install'],
  );

  return switch (result) {
    Ok<ReferralSummary>(:final value) => Response.json(
      body: ReferralSummaryDto(
        code: value.code,
        monthPoints: value.counts.monthPoints,
        seasonPoints: value.counts.seasonPoints,
        invitedCount: value.counts.invitedCount,
        pendingCount: value.counts.pendingCount,
        monthCap: value.monthCap,
      ).toJson(),
    ),
    Err<ReferralSummary>(:final error) => errorResponse(error),
  };
}
