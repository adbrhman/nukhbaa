import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/retention` -- do players come back (migration 0069): play
/// per week and players by the week of their first active day, over the
/// last `?weeks=` weeks (default 8, at most 26), the week in progress
/// included. Admin only: the gate lives in the use-case, as for every admin
/// read; a non-admin is refused as `401 auth.insufficient_role`. `405` on
/// any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final rawWeeks = context.request.uri.queryParameters['weeks'];

  final result = await root.adminGetRetention(
    principal: principal,
    weeks: rawWeeks == null ? null : int.tryParse(rawWeeks),
  );

  return switch (result) {
    Ok<RetentionStats>(:final value) => Response.json(
      body: AdminRetentionDto(
        today: _day(value.today),
        weeks: [
          for (final w in value.weeks)
            RetentionWeekDto(
              weekStart: _day(w.weekStart),
              complete: w.complete,
              activeUsers: w.activeUsers,
              active3Plus: w.active3Plus,
              leagueActive: w.leagueActive,
              leagueActive3Plus: w.leagueActive3Plus,
              leagueMembers: w.leagueMembers,
              leagueReturned: w.leagueReturned,
            ),
        ],
        cohorts: [
          for (final c in value.cohorts)
            RetentionCohortDto(
              weekStart: _day(c.weekStart),
              users: c.users,
              day1: RetentionRateDto(
                eligible: c.day1Eligible,
                retained: c.day1,
              ),
              day7: RetentionRateDto(
                eligible: c.day7Eligible,
                retained: c.day7,
              ),
              day14: RetentionRateDto(
                eligible: c.day14Eligible,
                retained: c.day14,
              ),
              week4: RetentionRateDto(
                eligible: c.week4Eligible,
                retained: c.week4,
              ),
            ),
        ],
      ).toJson(),
    ),
    Err<RetentionStats>(:final error) => errorResponse(error),
  };
}

/// A Riyadh day carried as a UTC midnight, as `YYYY-MM-DD`.
String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
