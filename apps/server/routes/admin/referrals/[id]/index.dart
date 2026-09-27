import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/referrals/{inviteeId}` -- approve or reject a held
/// invitation, or revoke a paid one (migration 0073). Body:
/// `{"decision": "approve" | "reject" | "revoke", "reason": "..."}`.
///
/// Admin only. A malformed id, decision or reason is `400`; every outcome
/// of a well-formed decision is `200` with its `status`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final dto = ReferralReviewRequestDto.fromJson(
    (bodyResult as Ok<Map<String, Object?>>).value,
  );

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminReviewReferral(
    principal: principal,
    inviteeId: id,
    decision: dto.decision,
    reason: dto.reason,
  );

  return switch (result) {
    Ok<ReferralReviewOutcome>(:final value) => Response.json(
      body: ReferralStatusDto(status: value.wireName).toJson(),
    ),
    Err<ReferralReviewOutcome>(:final error) => errorResponse(error),
  };
}
