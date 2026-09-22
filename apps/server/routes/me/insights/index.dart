import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /me/insights` -- the caller's accuracy, patterns and last week's
/// recap (plan P4-4), computed from their scored predictions on every read.
///
/// One endpoint instead of the plan's three (`/me/accuracy`,
/// `/me/insights`, `/me/weekly-recap`): they read the same rows, and the
/// screen shows them together.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getMyInsights(principal: principal);

  return switch (result) {
    Ok<MyInsights>(:final value) => Response.json(
      body: insightsDtoOf(value).toJson(),
    ),
    Err<MyInsights>(:final error) => errorResponse(error),
  };
}

/// Maps the use-case answer to the wire shape.
InsightsDto insightsDtoOf(MyInsights value) {
  final PredictionInsights insights = value.insights;
  final WeekRecap? recap = insights.lastWeek;
  final PredictionOutcome? best = recap?.best;
  return InsightsDto(
    month: _accuracy(insights.month),
    communityPercent: value.community.percent,
    leagues: [
      for (final league in insights.leagues)
        LeagueAccuracyDto(name: league.name, accuracy: _accuracy(league.tally)),
    ],
    bestLeague: insights.bestLeague,
    worstLeague: insights.worstLeague,
    followedPercent: insights.followed?.percent,
    othersPercent: insights.others?.percent,
    longestCorrectRun: insights.longestCorrectRun,
    weeks: [
      for (final week in insights.weeks)
        WeekAccuracyDto(
          weekStart: _date(week.weekStart),
          accuracy: _accuracy(week.tally),
        ),
    ],
    lastWeek: recap == null
        ? null
        : WeekRecapDto(
            weekStart: _date(recap.weekStart),
            accuracy: _accuracy(recap.tally),
            points: recap.points,
            best: best == null
                ? null
                : BestPredictionDto(
                    homeTeam: best.homeTeam,
                    awayTeam: best.awayTeam,
                    points: best.points,
                    exact: best.grade == PredictionGrade.exact,
                  ),
          ),
  );
}

AccuracyDto _accuracy(AccuracyTally tally) => AccuracyDto(
  decided: tally.decided,
  correct: tally.correct,
  exact: tally.exact,
  percent: tally.percent,
);

String _date(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
