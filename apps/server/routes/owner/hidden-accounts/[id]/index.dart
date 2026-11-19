import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

// NK287_01
/// `POST /owner/hidden-accounts/{id}` hides the account from every board;
/// `DELETE` shows it again with the same points (`OwnerHiddenAccounts`,
/// script 258, migration 0207). An owner seat alone: anyone else gets the
/// owner gate's `404` (script 287); no owner seat is ever hidden
/// (`409 admin.cannot_hide_owner`); an unknown account is
/// `409 admin.user_not_found`. Answers `{"hidden": true|false}`. `405`
/// on any other method.
Future<Response> onRequest(RequestContext context, String id) async {
  final HttpMethod method = context.request.method;
  if (method != HttpMethod.post && method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final accounts = root.ownerHiddenAccounts;
  if (accounts == null) {
    return errorResponse(
      const AppError.transient(
        'admin.hidden_accounts_unavailable',
        'The hidden accounts are unavailable',
      ),
    );
  }
  final bool hide = method == HttpMethod.post;
  final Result<void> result = hide
      ? await accounts.hide(principal: principal, targetUserId: id)
      : await accounts.show(principal: principal, targetUserId: id);

  return switch (result) {
    Ok<void>() => Response.json(body: {'hidden': hide}),
    Err<void>(:final error) => errorResponse(error),
  };
}
