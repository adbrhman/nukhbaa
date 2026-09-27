import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/referrals` -- the invitations held for review, oldest first
/// (migration 0073). `?limit=` (default 50, at most 100). Admin only: the
/// gate lives in the use-case; a non-admin is `401 auth.insufficient_role`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final rawLimit = context.request.uri.queryParameters['limit'];

  final result = await root.adminListHeldReferrals(
    principal: principal,
    limit: rawLimit == null ? null : int.tryParse(rawLimit),
  );

  return switch (result) {
    Ok<List<HeldReferral>>(:final value) => Response.json(
      body: AdminHeldReferralsDto(
        items: [
          for (final HeldReferral h in value)
            HeldReferralDto(
              inviteeId: h.inviteeId,
              inviteeName: h.inviteeName,
              referrerId: h.referrerId,
              referrerName: h.referrerName,
              claimedAt: h.claimedAt.toUtc().toIso8601String(),
              heldAt: h.heldAt.toUtc().toIso8601String(),
              reasons: h.reasons,
            ),
        ],
      ).toJson(),
    ),
    Err<List<HeldReferral>>(:final error) => errorResponse(error),
  };
}
