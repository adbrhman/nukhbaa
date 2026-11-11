import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/hidden-accounts` -- the accounts the owner admin hid from
/// every board, the most recently hidden first (`OwnerHiddenAccounts`,
/// script 258, migration 0207). The owner admin alone: any other admin is
/// `409 admin.owner_only`, a player is refused by the admin gate. `405` on
/// any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
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
  final result = await accounts.list(principal: principal);

  return switch (result) {
    Ok<List<HiddenAccount>>(:final value) => Response.json(
      body: HiddenAccountsDto(
        accounts: [
          for (final HiddenAccount account in value)
            HiddenAccountDto(
              user: userSummaryToDto(account.user),
              hiddenAt: account.hiddenAt,
            ),
        ],
      ).toJson(),
    ),
    Err<List<HiddenAccount>>(:final error) => errorResponse(error),
  };
}
