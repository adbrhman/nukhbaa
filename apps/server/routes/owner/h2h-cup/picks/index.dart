// NK313_01
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_cup_board_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /owner/h2h-cup/picks?month=YYYY-MM-01` -- the whole Elite Cup of a
/// month with EVERY player's picks on every fixture, before it kicks off
/// too (script 313). Read only. Without `month`, the latest month that
/// holds a cup.
///
/// The same wire shape as `/me/h2h-cup/board`, from the same mapper; here
/// every side is `revealed`, and a side with no pick means the player did
/// not predict. Behind the owner gate (`routes/owner/_middleware.dart`):
/// anyone but an owner seat gets the `404` of a path with no route, so an
/// admin sees nothing of it. A `month` that is not a date is
/// `400 owner.h2h_month_invalid`. `405` on any method but GET.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final raw = context.request.uri.queryParameters['month'];
  DateTime? month;
  if (raw != null) {
    month = DateTime.tryParse(raw);
    if (month == null) {
      return errorResponse(
        const AppError.validation(
          'owner.h2h_month_invalid',
          'month must be a date, as 2026-11-01',
        ),
      );
    }
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getOwnerH2hCupPicks(
    principal: principal,
    month: month,
  );

  return switch (result) {
    Ok<H2hCupBoard>(:final value) => Response.json(
      body: h2hCupBoardToDto(value).toJson(),
    ),
    Err<H2hCupBoard>(:final error) => errorResponse(error),
  };
}
