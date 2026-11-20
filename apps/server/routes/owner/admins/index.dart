import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

// NK294_05
/// `GET /owner/admins` -- every admin, whether each holds an owner seat,
/// and the owners' latest changes with their reasons (`OwnerAdmins`,
/// script 294, migration 0223).
///
/// Anyone but an owner seat gets the owner gate's `404` (script 287).
/// `405` on any other method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final OwnerAdmins? admins = root.ownerAdmins;
  if (admins == null) {
    return errorResponse(
      const AppError.transient(
        'owner.admins_unavailable',
        'The admins are unavailable',
      ),
    );
  }
  final Result<AdminRosterView> listed = await admins.list(
    principal: context.read<AuthenticatedUser>(),
  );
  return switch (listed) {
    Ok<AdminRosterView>(:final value) => Response.json(
      body: OwnerAdminsDto(
        admins: <OwnerAdminDto>[
          for (final AdminSeat seat in value.admins)
            OwnerAdminDto(
              id: seat.member.id.value,
              displayName: seat.member.displayName,
              email: seat.member.email,
              active: seat.member.active,
              isOwner: seat.owner,
            ),
        ],
        changes: <RoleChangeDto>[
          for (final RoleChange change in value.changes)
            RoleChangeDto(
              userName: change.userName,
              action: change.action,
              reason: change.reason,
              byName: change.byName,
              at: change.at,
              sessionsEnded: change.sessionsEnded,
            ),
        ],
      ).toJson(),
    ),
    Err<AdminRosterView>(:final error) => errorResponse(error),
  };
}
