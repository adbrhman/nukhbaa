import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_social_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `/groups/{id}/fixtures/{fixtureId}/reactions` — a group member's emoji
/// reaction to a fixture-result (docs/project-context.md, Axiom 4 Amendment —
/// the per-fixture sibling of
/// `routes/groups/[id]/rounds/[roundId]/reactions/index.dart`).
///
/// Lives UNDER `/groups/{id}/...` so it inherits the `/groups` `bearerAuth`
/// subtree and is group-scoped by construction. Every authorization decision
/// (the member-only `group.not_a_member` gate, no existence oracle) lives
/// inside the use-case; this route makes none.
///
/// Methods:
///   * `PUT` — react or change (idempotent upsert). Body: `{ "emoji": string }`.
///     → `200` [FixtureReactionDto].
///   * `DELETE` — remove the caller's own reaction (idempotent). → `200`
///     `{ "removed": bool }`.
///   * `GET` — list the fixture's reactions within the group (member-gated).
///     → `200` [FixtureReactionsDto].
///   * anything else → `405`.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  final method = context.request.method;
  return switch (method) {
    HttpMethod.put => _react(context, id, fixtureId),
    HttpMethod.delete => _remove(context, id, fixtureId),
    HttpMethod.get => _list(context, id, fixtureId),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

Future<Response> _react(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final emoji = requireString(body, 'emoji');
  if (emoji is Err<String>) {
    return errorResponse(emoji.error);
  }

  final result = await root.reactToFixture(
    principal: principal,
    groupId: id,
    fixtureId: fixtureId,
    emoji: (emoji as Ok<String>).value,
  );

  return switch (result) {
    Ok<FixtureReaction>(:final value) => Response.json(
      body: fixtureReactionToDto(value).toJson(),
    ),
    Err<FixtureReaction>(:final error) => errorResponse(error),
  };
}

Future<Response> _remove(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.removeFixtureReaction(
    principal: principal,
    groupId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<bool>(:final value) => Response.json(body: {'removed': value}),
    Err<bool>(:final error) => errorResponse(error),
  };
}

Future<Response> _list(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.listFixtureReactions(
    principal: principal,
    groupId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<List<FixtureReaction>>(:final value) => Response.json(
      body: fixtureReactionsJson(id, fixtureId, value),
    ),
    Err<List<FixtureReaction>>(:final error) => errorResponse(error),
  };
}
