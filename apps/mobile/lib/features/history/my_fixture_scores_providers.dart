/// The caller's own grades, points and final scores: one read for every
/// match card, history row, match screen and prediction sheet (script 75).
///
/// Before it each of them asked `GET /seasons/{id}/fixtures/{fixtureId}/scores`
/// for its own match -- every participant's score, to show one line -- and
/// asked again every 2 minutes while the score was pending. When a match
/// ended every player's app did that at once for every finished card and
/// every history row; on the night of 2026-10-14/15 the route timed out 389
/// times.
///
/// Hand-written (plain providers, no `@riverpod`) like
/// `prediction_lookup_providers.dart`: this file needs no build_runner
/// output.
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';

/// A row's key: the participant (one per season) and the fixture -- the
/// same pair a [FixturePredictionDto] carries.
typedef MyFixtureScoreKey = ({String participantId, String fixtureId});

/// How long a recorded result may wait for its grade before the read is
/// asked again.
const Duration myFixtureScoresRetryDelay = Duration(minutes: 2);

/// `GET /me/fixture-scores` -- every prediction of the caller that has a
/// score or a recorded result, keyed by [MyFixtureScoreKey].
///
/// Asked once the month's feed has answered; read again when the feed shows
/// a result it may not have seen (a match just ended), and every
/// [myFixtureScoresRetryDelay] while a recorded result still has no grade;
/// never otherwise. Kept for two minutes past
/// the last card that watched it, so scrolling a finished match away and
/// back asks nothing. A failure is an [AppError] the cards read as "no
/// verdict yet" (`.value` is null), exactly as while loading.
final myFixtureScoresProvider =
    FutureProvider.autoDispose<Map<MyFixtureScoreKey, MyFixtureScoreDto>>((
      ref,
    ) async {
      final link = ref.keepAlive();
      final Timer expiry = Timer(const Duration(minutes: 2), link.close);
      ref.onDispose(expiry.cancel);

      // Only the set of the month's fixtures with a recorded result: the
      // feed's own refreshes, while nothing new finished, change nothing.
      final String? recorded = ref.watch(
        currentMonthFixturesProvider.select(_recordedResults),
      );
      if (recorded == null) {
        // The feed's first load is still on its way, and its answer would
        // only ask again at once: wait for it (it rebuilds this provider).
        return Completer<Map<MyFixtureScoreKey, MyFixtureScoreDto>>().future;
      }

      final CompetitionApi api = ref.watch(competitionApiProvider);
      final result = await api.myFixtureScores();
      switch (result) {
        case Ok<List<MyFixtureScoreDto>>(:final value):
          if (value.any(_waitingForGrade)) {
            final Timer retry = Timer(
              myFixtureScoresRetryDelay,
              ref.invalidateSelf,
            );
            ref.onDispose(retry.cancel);
          }
          return Map<MyFixtureScoreKey, MyFixtureScoreDto>.unmodifiable(<
            MyFixtureScoreKey,
            MyFixtureScoreDto
          >{
            for (final MyFixtureScoreDto row in value)
              (participantId: row.participantId, fixtureId: row.fixtureId): row,
          });
        case Err<List<MyFixtureScoreDto>>(:final error):
          throw error;
      }
    });

/// The row of [prediction] in [rows] (a [myFixtureScoresProvider] value),
/// or null while there is none -- not scored, no result, still loading, or
/// a failed read.
MyFixtureScoreDto? myFixtureScoreOf(
  Map<MyFixtureScoreKey, MyFixtureScoreDto>? rows,
  FixturePredictionDto prediction,
) =>
    rows?[(
      participantId: prediction.participantId,
      fixtureId: prediction.fixtureId,
    )];

/// The month's fixtures that have a recorded result, as one stable string;
/// null while the feed's first load is in flight. A feed that failed counts
/// as no result: the read goes ahead.
String? _recordedResults(AsyncValue<List<CurrentMonthFixtureItemDto>> feed) {
  if (!feed.hasValue && !feed.hasError) return null;
  final List<String> ids = <String>[
    for (final CurrentMonthFixtureItemDto item
        in feed.value ?? const <CurrentMonthFixtureItemDto>[])
      if (item.resultHomeGoals != null && item.resultAwayGoals != null)
        item.fixture.fixtureId,
  ]..sort();
  return ids.join(',');
}

/// A recorded result whose call has no final verdict yet.
bool _waitingForGrade(MyFixtureScoreDto row) =>
    row.resultHomeGoals != null &&
    row.grade != 'exact_scoreline' &&
    row.grade != 'correct_outcome' &&
    row.grade != 'incorrect';
