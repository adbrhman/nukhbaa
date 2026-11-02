import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/shared-devices` -- every phone more than one account was
/// seen on (`AdminListSharedDevices`, script 200), as a [SharedDevicesDto]
/// (`200`): its accounts with their status, and when it was last seen. An
/// empty `devices` list means every phone holds one account. Admin-only;
/// `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final list = root.adminListSharedDevices;
  if (list == null) {
    return errorResponse(
      const AppError.transient(
        'admin.shared_devices_unavailable',
        'The shared-devices list is unavailable',
      ),
    );
  }
  final result = await list(principal: principal);

  return switch (result) {
    Ok<List<SharedDeviceGroup>>(:final value) => Response.json(
      body: SharedDevicesDto(
        devices: [
          for (final group in value)
            SharedDeviceDto(
              users: [for (final user in group.users) userSummaryToDto(user)],
              lastSeen: group.lastSeen,
            ),
        ],
      ).toJson(),
    ),
    Err<List<SharedDeviceGroup>>(:final error) => errorResponse(error),
  };
}
