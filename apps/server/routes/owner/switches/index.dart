import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/owner_switch_wire.dart';
import 'package:shared/shared.dart';

// NK289_05
/// `GET /owner/switches` -- the owners' switches, each with its state and
/// its last change (`OwnerSwitchBoard`, script 289, migration 0218). First
/// the month's crowning.
///
/// Anyone but an owner seat gets the owner gate's `404` (script 287).
/// `405` on any other method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final board = root.ownerSwitchBoard;
  if (board == null) {
    return errorResponse(
      const AppError.transient(
        'owner.switches_unavailable',
        'The owner switches are unavailable',
      ),
    );
  }
  final principal = context.read<AuthenticatedUser>();
  final Result<List<OwnerSwitchState>> listed = await board.list(
    principal: principal,
  );
  return switch (listed) {
    Ok<List<OwnerSwitchState>>(:final value) => Response.json(
      body: OwnerSwitchesDto(
        switches: <OwnerSwitchDto>[
          for (final OwnerSwitchState state in value)
            ownerSwitchWire(state, principal.userId),
        ],
      ).toJson(),
    ),
    Err<List<OwnerSwitchState>>(:final error) => errorResponse(error),
  };
}
