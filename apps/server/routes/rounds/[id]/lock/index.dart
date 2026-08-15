import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// POST /rounds/{id}/lock — lock an open round once its prediction window closes
/// (API ADR §2: command intent `LockRound`). Admin-only (use-case layer).
///
/// This is modelled as a sub-resource command (`/lock`) rather than a status
/// mutation, keeping the surface a use-case API of domain intents rather than
/// tables-over-HTTP. No body. Returns the updated [RoundDto] (`200`); a stale
/// or concurrent attempt surfaces as `409` via the error envelope.
///
/// Locking a round is also the event that typically flips the NEXT round's
/// `isPredictable` to `true` (the sequential-round gate) — so this response's
/// own [RoundDto.isPredictable] is still computed against the season's rounds
/// for consistency, even though it is trivially `false` for the round that was
/// just locked.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.lockRound(principal: principal, roundId: id);
  if (result is Err<Round>) return errorResponse(result.error);
  final locked = (result as Ok<Round>).value;

  final seasonRoundsResult = await root.listSeasonRounds(
    principal: principal,
    seasonId: locked.seasonId.value,
  );
  if (seasonRoundsResult is Err<List<Round>>) {
    return errorResponse(seasonRoundsResult.error);
  }
  final seasonRounds = (seasonRoundsResult as Ok<List<Round>>).value;

  return Response.json(
    body: roundToDto(locked, seasonRounds: seasonRounds).toJson(),
  );
}
