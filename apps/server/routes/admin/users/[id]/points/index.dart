import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/users/{id}/points?season={seasonId}` -- one player's points
/// in one month (batch 146b, audit C-01 and L-14): every movement of the
/// fixture ledger with its match's sides, the month's points as its board
/// counts them and the streak bonuses apart. Backs the admin's "سجل
/// النقاط", picked by name and month instead of a participant id typed by
/// hand, and replaces its read of the empty round ledger. Admin only,
/// audited as `participant_ledger_viewed`: the gate and the trace live in
/// the use-case. A month the player never played is `played: false`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final String season =
      context.request.uri.queryParameters['season']?.trim() ?? '';

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminViewPlayerPoints(
    principal: principal,
    userId: id,
    seasonId: season,
  );

  return switch (result) {
    Ok<PlayerMonthPoints>(:final value) => Response.json(
      body: PlayerMonthPointsDto(
        played: value.participantId != null,
        monthPoints: value.monthPoints,
        streakBonus: value.streakBonus,
        entries: <PlayerPointEntryDto>[
          for (final PlayerPointEntry e in value.entries)
            PlayerPointEntryDto(
              id: e.id,
              fixtureId: e.fixtureId,
              homeTeam: e.homeTeam,
              awayTeam: e.awayTeam,
              kind: e.kind,
              amount: e.amount,
              occurredAt: e.occurredAt.toUtc().toIso8601String(),
            ),
        ],
      ).toJson(),
    ),
    Err<PlayerMonthPoints>(:final error) => errorResponse(error),
  };
}
