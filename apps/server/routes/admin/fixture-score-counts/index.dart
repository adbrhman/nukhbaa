import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/fixture-score-counts?fixtures=a,b,...` -- how many players
/// were scored on each named fixture, in one query (batch 156). Backs the
/// admin's "المباريات المحتسبة", which sent one request per match played
/// this month. At most 200 ids (`admin.too_many_fixtures`). Admin only:
/// the gate lives in the use-case.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final String raw =
      context.request.uri.queryParameters['fixtures']?.trim() ?? '';
  final List<String> ids = <String>[
    for (final String id in raw.split(','))
      if (id.trim().isNotEmpty) id.trim(),
  ];

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminCountFixtureScores(
    principal: principal,
    fixtureIds: ids,
  );

  return switch (result) {
    Ok<Map<String, int>>(:final value) => Response.json(
      body: FixtureScoreCountsDto(counts: value).toJson(),
    ),
    Err<Map<String, int>>(:final error) => errorResponse(error),
  };
}
