import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `/admin/person-links/{mainId}` -- one person's accounts, linked by the
/// owner admin alone (`OwnerPersonLinks`, script 263, migration 0209).
///
/// * `PUT` `{"second_id": "...", "other_ids": ["..."]}` -- the main account
///   and the second (optional) count; the others are hidden from every
///   board. Setting it again changes it; what leaves is shown again.
///   Answers `{"set": true}`.
/// * `DELETE` -- unlinks the person, showing again what the link hid.
///   Answers `{"unlinked": n}`.
///
/// Any other admin is `409 admin.owner_only`; under two accounts is
/// `400 admin.person_too_few`; an account named twice is
/// `400 admin.person_duplicate`; an unknown account is
/// `409 admin.user_not_found`; one linked to another person is
/// `409 admin.person_account_taken`; the owner as an other account is
/// `409 admin.cannot_hide_owner`. `405` on any other method.
Future<Response> onRequest(RequestContext context, String id) async {
  final HttpMethod method = context.request.method;
  if (method != HttpMethod.put && method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final links = root.ownerPersonLinks;
  if (links == null) {
    return errorResponse(
      const AppError.transient(
        'admin.person_links_unavailable',
        'The linked accounts are unavailable',
      ),
    );
  }

  if (method == HttpMethod.delete) {
    final Result<int> unlinked = await links.unlink(
      principal: principal,
      mainId: id,
    );
    return switch (unlinked) {
      Ok<int>(:final value) => Response.json(body: {'unlinked': value}),
      Err<int>(:final error) => errorResponse(error),
    };
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final SetPersonRequestDto request = SetPersonRequestDto.fromJson(
    (bodyResult as Ok<Map<String, Object?>>).value,
  );
  final Result<void> set = await links.set(
    principal: principal,
    mainId: id,
    secondId: request.secondId,
    otherIds: request.otherIds,
  );
  return switch (set) {
    Ok<void>() => Response.json(body: {'set': true}),
    Err<void>(:final error) => errorResponse(error),
  };
}
