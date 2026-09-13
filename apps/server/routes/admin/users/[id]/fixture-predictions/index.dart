import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_user_prediction_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/users/{id}/fixture-predictions` — prediction history for ONE
/// selected user. The read is admin-only inside the application use-case and
/// is audited before data is returned.
///
/// `from` is inclusive and `to` is exclusive. Both must be present together
/// when a date filter is requested; the mobile client sends UTC boundaries for
/// the device-local day.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final query = context.request.uri.queryParameters;
  final from = _parseUtc(query['from']);
  final to = _parseUtc(query['to']);
  if ((query['from'] != null && from == null) ||
      (query['to'] != null && to == null)) {
    return errorResponse(
      const AppError.validation(
        'admin.predictions_invalid_range',
        'Invalid date range',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.adminGetUserFixturePredictions(
    principal: principal,
    userId: id,
    fromUtc: from,
    toUtc: to,
  );

  return switch (result) {
    Ok<AdminUserPredictionHistory>(:final value) => Response.json(
      body: adminUserPredictionHistoryToDto(value).toJson(),
    ),
    Err<AdminUserPredictionHistory>(:final error) => errorResponse(error),
  };
}

DateTime? _parseUtc(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
