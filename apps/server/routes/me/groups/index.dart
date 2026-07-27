import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/group_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /me/groups — lists every group the caller belongs to ("My Groups";
/// API ADR §2: a query, command/query separated).
///
/// This is an OWNERSHIP read, not a per-group membership check (mirror of
/// `GET /participants/{id}/balance`'s "only my own ledger" shape, distinct
/// from `GET /groups/{id}`'s member-only visibility gate): the caller always
/// reads their own roster, so there is no `group.not_a_member` refusal here —
/// what varies is only which groups come back (possibly none). The request is
/// already authenticated by `routes/me/_middleware.dart`'s `bearerAuth`.
///
/// Returns a [MyGroupsDto] ordered by joined-at descending (the caller's most
/// recently joined group first), each entry carrying the group (including its
/// invite code — a capability the caller already holds as a member of every
/// row here), the caller's own [GroupRole] wire token, and when they joined.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listMyGroups(principal: principal);

  return switch (result) {
    Ok<List<MyGroupSummary>>(:final value) => Response.json(
      body: myGroupsJson(value),
    ),
    Err<List<MyGroupSummary>>(:final error) => errorResponse(error),
  };
}
