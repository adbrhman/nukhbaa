import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/person-links` -- every person the owner admin linked, each
/// with its accounts, the main one first (`OwnerPersonLinks`, script 263,
/// migration 0209). The owner admin alone: any other admin is
/// `409 admin.owner_only`, a player is refused by the admin gate. `405` on
/// any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final links = root.ownerPersonLinks;
  if (links == null) {
    return errorResponse(
      const AppError.transient(
        'admin.person_links_unavailable',
        'The linked accounts are unavailable',
      ),
    );
  }
  final result = await links.list(principal: context.read<AuthenticatedUser>());

  return switch (result) {
    Ok<List<LinkedPerson>>(:final value) => Response.json(
      body: PersonLinksDto(
        people: [
          for (final LinkedPerson person in value)
            LinkedPersonDto(
              mainId: person.main.value,
              accounts: [
                for (final LinkedAccount account in person.accounts)
                  LinkedAccountDto(
                    user: userSummaryToDto(account.user),
                    counted: account.counted,
                    hidden: account.hidden,
                  ),
              ],
            ),
        ],
      ).toJson(),
    ),
    Err<List<LinkedPerson>>(:final error) => errorResponse(error),
  };
}
