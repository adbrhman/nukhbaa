import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/new-players?days=` -- the players who joined in the last
/// `days` days (default 7, at most 30), newest first
/// (`AdminListNewPlayers`, script 202): the screen the new-player push
/// opens. Each player carries the names like his (`similar_to`, script
/// 263). Admin-only; `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final list = root.adminListNewPlayers;
  if (list == null) {
    return errorResponse(
      const AppError.transient(
        'admin.new_players_unavailable',
        'The new-players list is unavailable',
      ),
    );
  }
  final int days =
      int.tryParse(context.request.uri.queryParameters['days'] ?? '') ?? 7;
  final result = await list(principal: principal, days: days);

  return switch (result) {
    Ok<List<NewPlayer>>(:final value) => Response.json(
      body: NewPlayersDto(
        days: days < 1
            ? 1
            : (days > AdminListNewPlayers.maxDays
                  ? AdminListNewPlayers.maxDays
                  : days),
        players: [
          for (final NewPlayer player in value)
            NewPlayerDto(
              user: userSummaryToDto(player.user),
              joinedAt: player.joinedAt,
              phoneAccounts: player.phoneAccounts,
              predictions: player.predictions,
              nameHint: switch (player.nameHint) {
                NewPlayerNameHint.automatic => 'automatic',
                NewPlayerNameHint.digits => 'digits',
                NewPlayerNameHint.oneWord => 'one_word',
                NewPlayerNameHint.title => 'title',
                NewPlayerNameHint.latin => 'latin',
                null => null,
              },
              similarTo: player.similarTo,
            ),
        ],
      ).toJson(),
    ),
    Err<List<NewPlayer>>(:final error) => errorResponse(error),
  };
}
