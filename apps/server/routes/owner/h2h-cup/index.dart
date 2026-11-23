import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/owner_h2h_cup_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /owner/h2h-cup?month=YYYY-MM-01` -- the whole Elite Cup of a month
/// for the owners' page (script 304): the month's rounds and the three
/// paths with their qualifiers, stages, pairs, results and titles. Without
/// `month`, the latest month that holds a cup.
///
/// Anyone but an owner seat gets the owner gate's `404` (script 287), so an
/// admin sees nothing of it. A `month` that is not a date is
/// `400 owner.h2h_month_invalid`. `405` on any other method.
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

  final result = await root.getOwnerH2hCup(principal: principal, month: month);

  return switch (result) {
    Ok<OwnerH2hCup>(:final value) => Response.json(
      body: ownerH2hCupToDto(value).toJson(),
    ),
    Err<OwnerH2hCup>(:final error) => errorResponse(error),
  };
}
