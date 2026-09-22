/// Use-case: the caller's accuracy, patterns and last week's recap.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/gamification/ports/prediction_outcome_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What `GET /me/insights` answers (plan P4-4).
final class MyInsights {
  /// Creates the answer.
  const MyInsights({required this.insights, required this.community});

  /// The caller's own insights.
  final PredictionInsights insights;

  /// Every player's accuracy this Riyadh month, for comparison.
  final AccuracyTally community;
}

/// Computes the caller's insights on every read (plan P4-1..P4-4): see
/// [PredictionInsights] for why nothing is stored.
///
/// Only the caller's own, always: the principal is the whole of the
/// authority check.
///
/// Never throws; returns a typed [Result].
final class GetMyInsights {
  /// Creates the use-case over its collaborators.
  const GetMyInsights({
    required PredictionOutcomeReader outcomes,
    required Clock clock,
  }) : _outcomes = outcomes,
       _clock = clock;

  final PredictionOutcomeReader _outcomes;
  final Clock _clock;

  /// Reads [principal]'s insights as of now.
  Future<Result<MyInsights>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final DateTime now = _clock.nowUtc();
    final DateTime today = PredictionInsights.riyadhDayOf(now);
    final DateTime from = PredictionInsights.windowStart(
      today,
    ).subtract(PredictionInsights.riyadhOffset);
    final DateTime monthStart = DateTime.utc(
      today.year,
      today.month,
    ).subtract(PredictionInsights.riyadhOffset);

    final outcomesResult = await _outcomes.outcomesOf(
      userId: principal.userId,
      from: from,
      to: now,
    );
    if (outcomesResult is Err<List<PredictionOutcome>>) {
      return Result.err(outcomesResult.error);
    }
    final communityResult = await _outcomes.communityTally(
      from: monthStart,
      to: now,
    );
    if (communityResult is Err<AccuracyTally>) {
      return Result.err(communityResult.error);
    }

    return Result.ok(
      MyInsights(
        insights: PredictionInsights.compute(
          outcomes: (outcomesResult as Ok<List<PredictionOutcome>>).value,
          today: today,
        ),
        community: (communityResult as Ok<AccuracyTally>).value,
      ),
    );
  }
}
