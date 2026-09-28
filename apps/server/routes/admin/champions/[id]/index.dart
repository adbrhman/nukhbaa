import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/champion_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// The crowning of a monthly contest (migration 0077). Admin only.
///
/// * `GET /admin/champions/{seasonId}` -- the preview: whether the month is
///   over, how many of its fixtures still have no result, who is already
///   crowned, and the top of its final board (everyone ranked first
///   included).
/// * `POST /admin/champions/{seasonId}` -- crowns the month. Body:
///   `{"user_ids": ["..."], "force": false}` -- one player, or two level
///   on every tie-break; `force` confirms crowning while some fixture has
///   no result. Answers the month's champions.
///
/// Refusals are `409` with their codes (`champion.month_not_over`,
/// `champion.already_crowned`, `champion.fixtures_unscored`,
/// `champion.not_first`); a malformed body is `400`; a non-admin `401`.
Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _preview(context, id),
    HttpMethod.post => _crown(context, id),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

Future<Response> _preview(RequestContext context, String id) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminGetChampionCandidates(
    principal: principal,
    seasonId: id,
  );

  return switch (result) {
    Ok<ChampionCandidates>(:final value) => Response.json(
      body: championCandidatesToDto(value).toJson(),
    ),
    Err<ChampionCandidates>(:final error) => errorResponse(error),
  };
}

Future<Response> _crown(RequestContext context, String id) async {
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminCrownMonthChampions(
    principal: principal,
    seasonId: id,
    userIds: CrownChampionsDto.userIdsOf(body),
    force: CrownChampionsDto.forceOf(body),
  );

  return switch (result) {
    Ok<List<MonthChampion>>(:final value) => Response.json(
      body: monthChampionsToDto(value).toJson(),
    ),
    Err<List<MonthChampion>>(:final error) => errorResponse(error),
  };
}
