/// Use-case: keep which screens a player opened (migration 0093).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/screen_view_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Adds one report of screen opens to the caller's rows of the current
/// Riyadh day, the day every other gamification measure uses.
///
/// A name outside [ScreenName.all] is dropped rather than refused: an app
/// newer than the server must not lose the rest of its report. A count
/// that cannot be true (below one, or above [maxOpensPerScreen]) and a
/// report naming more than [maxScreens] screens are refused: they are noise,
/// and the app never waits on the answer.
///
/// Never throws; returns a typed [Result] carrying how many screens were
/// kept.
final class RecordScreenViews {
  /// Creates the use-case over its collaborators.
  const RecordScreenViews({
    required ScreenViewRepository views,
    required Clock clock,
  }) : _views = views,
       _clock = clock;

  final ScreenViewRepository _views;
  final Clock _clock;

  /// The most screens one report may name.
  static const int maxScreens = 64;

  /// The most opens of one screen one report may claim.
  static const int maxOpensPerScreen = 1000;

  /// Keeps [opens] (screen name to how many times it was opened) from
  /// [principal].
  Future<Result<int>> call({
    required AuthenticatedUser principal,
    required Map<String, int> opens,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    if (opens.length > maxScreens) {
      return const Result.err(
        AppError.validation(
          'screen_views.too_many',
          'A report may name at most $maxScreens screens',
        ),
      );
    }
    for (final int count in opens.values) {
      if (count < 1 || count > maxOpensPerScreen) {
        return const Result.err(
          AppError.validation(
            'screen_views.invalid_count',
            'Each count must be between 1 and $maxOpensPerScreen',
          ),
        );
      }
    }
    final Map<String, int> known = <String, int>{
      for (final MapEntry<String, int> e in opens.entries)
        if (ScreenName.all.contains(e.key)) e.key: e.value,
    };
    if (known.isEmpty) {
      return const Result.ok(0);
    }
    final DateTime now = _clock.nowUtc();
    final Result<void> added = await _views.add(
      userId: principal.userId,
      day: riyadhDayOf(now),
      opens: known,
      reportedAt: now,
    );
    return switch (added) {
      Err<void>(:final error) => Result.err(error),
      Ok<void>() => Result.ok(known.length),
    };
  }
}
