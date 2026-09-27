import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/referral-overview` -- the invitation system for the admin
/// page (migration 0075): the switch, the totals per state, the inviters
/// and the newest invitations. Admin only; a non-admin is
/// `401 auth.insufficient_role`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminGetReferralOverview(principal: principal);

  return switch (result) {
    Ok<ReferralOverview>(:final value) => Response.json(
      body: AdminReferralOverviewDto(
        enabled: value.enabled,
        stateCounts: value.stateCounts,
        referrers: [
          for (final ReferrerTotals r in value.referrers)
            ReferrerTotalsDto(
              referrerId: r.referrerId,
              referrerName: r.referrerName,
              invited: r.invited,
              paid: r.paid,
              pending: r.pending,
              held: r.held,
              refused: r.refused,
              monthPoints: r.monthPoints,
            ),
        ],
        invitations: [
          for (final ReferralInvitation i in value.invitations)
            ReferralInvitationDto(
              inviteeId: i.inviteeId,
              inviteeName: i.inviteeName,
              inviteeStatus: i.inviteeStatus,
              referrerId: i.referrerId,
              referrerName: i.referrerName,
              claimedAt: i.claimedAt.toUtc().toIso8601String(),
              state: i.state,
              holdReasons: i.holdReasons,
              paidAt: i.paidAt?.toUtc().toIso8601String(),
              heldAt: i.heldAt?.toUtc().toIso8601String(),
              revokedAt: i.revokedAt?.toUtc().toIso8601String(),
              revokeReason: i.revokeReason,
              lastPredictionAt: i.lastPredictionAt?.toUtc().toIso8601String(),
            ),
        ],
      ).toJson(),
    ),
    Err<ReferralOverview>(:final error) => errorResponse(error),
  };
}
