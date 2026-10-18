import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `DELETE /me/account` -- the caller deletes his own account (audit M-05,
/// migration 0178, script 113).
///
/// No body: the account comes from the verified token, never the request.
/// The account is anonymised for good (its points and predictions stay in
/// the record) and its sign-in erased; the answer is `{"deleted": true}`,
/// also when it was already deleted. An admin's account is refused (409).
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final deleteMyAccount = root.deleteMyAccount;
  if (deleteMyAccount == null) {
    return errorResponse(
      const AppError.transient(
        'identity.account_deletion_unwired',
        'Account deletion is not available',
      ),
    );
  }
  final principal = context.read<AuthenticatedUser>();

  final result = await deleteMyAccount(principal: principal);

  return switch (result) {
    Ok<void>() => Response.json(body: const <String, Object?>{'deleted': true}),
    Err<void>(:final error) => errorResponse(error),
  };
}
