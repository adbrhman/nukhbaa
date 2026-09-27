import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /me/referral/claim` -- a new account names the code of the friend
/// who invited it (migration 0073). Body: `{"code": "...", "install_id":
/// "..."}`.
///
/// Every outcome of the claim is `200` with its `status`; the app words
/// each one. A body that is not a JSON object is `400`. The network address
/// is the last hop of `X-Forwarded-For` (the one the platform's proxy
/// added, which the client cannot forge), sent only to be hashed.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final dto = ReferralClaimRequestDto.fromJson(
    (bodyResult as Ok<Map<String, Object?>>).value,
  );

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.claimReferral(
    principal: principal,
    code: dto.code,
    ip: _clientIp(context.request.headers),
    installId: dto.installId,
  );

  return switch (result) {
    Ok<ReferralClaimOutcome>(:final value) => Response.json(
      body: ReferralStatusDto(status: value.wireName).toJson(),
    ),
    Err<ReferralClaimOutcome>(:final error) => errorResponse(error),
  };
}

String? _clientIp(Map<String, String> headers) {
  final String? forwarded = headers['x-forwarded-for'];
  if (forwarded != null) {
    final List<String> hops = [
      for (final String hop in forwarded.split(','))
        if (hop.trim().isNotEmpty) hop.trim(),
    ];
    if (hops.isNotEmpty) {
      return hops.last;
    }
  }
  final String? real = headers['x-real-ip']?.trim();
  return real == null || real.isEmpty ? null : real;
}
