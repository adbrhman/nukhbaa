import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/support_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/support/conversations` -- the admins' support inbox
/// (migration 0187): conversations by their last message, newest first,
/// at most 100. `?filter=` `all` (default), `unread`, `open` or `closed`
/// (closed and archived); `?search=` part of the player's name. Also how
/// many conversations wait for an admin, whatever the filter.
///
/// Admin only: the gate lives in the use-case, as for every admin read; a
/// non-admin is refused as `401 auth.insufficient_role`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final query = context.request.uri.queryParameters;
  final result = await root.adminGetSupportInbox(
    principal: principal,
    filter: query['filter'],
    search: query['search'],
  );
  return switch (result) {
    Ok<SupportInbox>(:final value) => Response.json(
      body: SupportInboxDto(
        unreadConversations: value.unreadConversations,
        conversations: [
          for (final SupportConversationSummary c in value.conversations)
            supportConversationDto(c),
        ],
      ).toJson(),
    ),
    Err<SupportInbox>(:final error) => errorResponse(error),
  };
}
